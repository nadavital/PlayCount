import CloudKit
import Foundation

protocol RecapCloudSyncClient {
    func isAvailable() async -> Bool
    func fetchSnapshotPayloads() async throws -> [RecapSnapshotSyncPayload]
    func saveSnapshotPayloads(_ payloads: [RecapSnapshotSyncPayload]) async throws
}

final class RecapCloudSyncService {
    private let client: RecapCloudSyncClient
    private let uploadsEnabled: Bool

    init(client: RecapCloudSyncClient, uploadsEnabled: Bool = true) {
        self.client = client
        self.uploadsEnabled = uploadsEnabled
    }

    static func live(uploadsEnabled: Bool = true) -> RecapCloudSyncService {
        RecapCloudSyncService(client: CloudKitRecapSyncClient(), uploadsEnabled: uploadsEnabled)
    }

    @discardableResult
    func sync(snapshotStore: MonthlyRecapSnapshotStore) async -> Bool {
        guard await client.isAvailable() else {
            #if DEBUG
            print("Recap CloudKit sync skipped: account unavailable")
            #endif
            return false
        }

        do {
            let remotePayloads: [RecapSnapshotSyncPayload]
            do {
                remotePayloads = try await client.fetchSnapshotPayloads()
            } catch {
                guard Self.isEmptyCloudKitStoreError(error) else {
                    throw error
                }
                remotePayloads = []
            }
            #if DEBUG
            print("Recap CloudKit sync fetched \(remotePayloads.count) remote payloads")
            #endif
            var preMergeLocalPayloads: [RecapSnapshotSyncPayload] = []
            if uploadsEnabled {
                preMergeLocalPayloads = snapshotStore.localSyncPayloads()
                #if DEBUG
                print("Recap CloudKit sync saving \(preMergeLocalPayloads.count) local payloads before merge")
                #endif
                try await client.saveSnapshotPayloads(preMergeLocalPayloads)
            }

            let didMergeRemote = snapshotStore.mergeSyncPayloads(remotePayloads)
            if uploadsEnabled {
                let localPayloads = snapshotStore.localSyncPayloads()
                if localPayloads != preMergeLocalPayloads {
                    #if DEBUG
                    print("Recap CloudKit sync saving \(localPayloads.count) local payloads after merge; didMergeRemote=\(didMergeRemote)")
                    #endif
                    try await client.saveSnapshotPayloads(localPayloads)
                } else {
                    #if DEBUG
                    print("Recap CloudKit sync upload unchanged after merge; didMergeRemote=\(didMergeRemote)")
                    #endif
                }
            } else {
                #if DEBUG
                print("Recap CloudKit sync upload skipped; didMergeRemote=\(didMergeRemote)")
                #endif
            }
            #if DEBUG
            print("Recap CloudKit sync finished")
            #endif
            return didMergeRemote
        } catch {
            #if DEBUG
            print("Recap CloudKit sync failed: \(error)")
            #endif
            return false
        }
    }

    private static func isEmptyCloudKitStoreError(_ error: Error) -> Bool {
        guard let cloudKitError = error as? CKError else { return false }
        return cloudKitError.code == .unknownItem
    }
}

final class CloudKitRecapSyncClient: RecapCloudSyncClient {
    private enum Field {
        static let capturedAt = "capturedAt"
        static let counterSignature = "counterSignature"
        static let payload = "payload"
        static let payloadIDs = "payloadIDs"
    }

    private static let containerIdentifier = "iCloud.com.nadavavital.PlayCount"
    private static let recordZoneName = "RecapSnapshots"
    private static let recordZoneID = CKRecordZone.ID(
        zoneName: recordZoneName,
        ownerName: CKCurrentUserDefaultName
    )

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "RecapSnapshot"
    private let manifestRecordType = "RecapSnapshotManifest"
    private let manifestRecordName = "current"
    private let fetchBatchSize = 10
    private let saveBatchSize = 10

    init(container: CKContainer = CKContainer(identifier: containerIdentifier)) {
        self.container = container
        database = container.privateCloudDatabase
    }

    func isAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, error in
                #if DEBUG
                if let error {
                    print("Recap CloudKit account status error: \(error)")
                } else {
                    print("Recap CloudKit account status: \(status.rawValue)")
                }
                #endif
                continuation.resume(returning: status == .available)
            }
        }
    }

    func fetchSnapshotPayloads() async throws -> [RecapSnapshotSyncPayload] {
        do {
            try await saveRecordZoneIfNeeded()
            let payloadIDs = try await fetchManifestPayloadIDs()
            let manifestPayloads = payloadIDs.isEmpty ? [] : try await fetchPayloadRecords(payloadIDs: payloadIDs)
            if !payloadIDs.isEmpty {
                return Self.resolvedFetchedPayloads(
                    manifestPayloadIDs: payloadIDs,
                    manifestPayloads: manifestPayloads,
                    zonePayloads: []
                )
            }

            let zonePayloads = try await fetchPayloadsFromZone(zoneID: Self.recordZoneID)
            return Self.resolvedFetchedPayloads(
                manifestPayloadIDs: payloadIDs,
                manifestPayloads: manifestPayloads,
                zonePayloads: zonePayloads
            )
        } catch {
            guard Self.isMissingZoneError(error) || Self.isMissingManifestError(error) else { throw error }
            #if DEBUG
            print("Recap CloudKit sync manifest unavailable: \(error)")
            #endif
            try await saveRecordZoneIfNeeded()
            return []
        }
    }

    func saveSnapshotPayloads(_ payloads: [RecapSnapshotSyncPayload]) async throws {
        guard !payloads.isEmpty else { return }
        try await saveRecordZoneIfNeeded()

        var seenPayloadIDs = Set<String>()
        let uniquePayloads = payloads.filter { payload in
            seenPayloadIDs.insert(payload.id).inserted
        }

        let records = uniquePayloads.map { payload in
            let recordID = CKRecord.ID(recordName: payload.id, zoneID: Self.recordZoneID)
            let record = CKRecord(recordType: recordType, recordID: recordID)
            record[Field.capturedAt] = payload.capturedAt as NSDate
            record[Field.counterSignature] = payload.counterSignature as NSString
            record[Field.payload] = payload.encodedSnapshot as NSData
            return record
        }

        for chunk in records.chunked(into: saveBatchSize) {
            try await modify(recordsToSave: chunk)
        }

        try await saveManifest(payloadIDs: Self.manifestPayloadIDs(for: uniquePayloads))
    }

    private func fetchPayloadsFromZone(zoneID: CKRecordZone.ID) async throws -> [RecapSnapshotSyncPayload] {
        let accumulator = PayloadAccumulator()
        try await fetchPayloadsFromZone(
            zoneID: zoneID,
            previousServerChangeToken: nil,
            into: accumulator
        )
        return accumulator.values
    }

    private func fetchPayloadsFromZone(
        zoneID: CKRecordZone.ID,
        previousServerChangeToken: CKServerChangeToken?,
        into payloads: PayloadAccumulator
    ) async throws {
        let fetchChangesResult: (CKServerChangeToken?, Bool) = try await withCheckedThrowingContinuation { continuation in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.previousServerChangeToken = previousServerChangeToken
            configuration.desiredKeys = [Field.capturedAt, Field.counterSignature, Field.payload]

            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.recordChangedBlock = { record in
                guard record.recordType == self.recordType,
                      let payload = Self.payload(from: record) else {
                    return
                }
                payloads.append(payload)
            }

            var nextToken: CKServerChangeToken?
            var moreComing = false
            var zoneError: Error?
            operation.recordZoneFetchCompletionBlock = { _, serverChangeToken, _, zoneMoreComing, error in
                zoneError = error
                nextToken = serverChangeToken
                moreComing = zoneMoreComing
            }
            operation.fetchRecordZoneChangesCompletionBlock = { error in
                if let error = zoneError ?? error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (nextToken, moreComing))
                }
            }

            operation.qualityOfService = .utility
            database.add(operation)
        }

        if fetchChangesResult.1, let nextToken = fetchChangesResult.0 {
            try await fetchPayloadsFromZone(
                zoneID: zoneID,
                previousServerChangeToken: nextToken,
                into: payloads
            )
        }
    }

    private func fetchManifestPayloadIDs() async throws -> [String] {
        let recordID = CKRecord.ID(recordName: manifestRecordName, zoneID: Self.recordZoneID)
        let record = try await fetchRecord(withID: recordID)
        guard let data = (record[Field.payloadIDs] as? Data) ?? (record[Field.payloadIDs] as? NSData).map({ $0 as Data }) else {
            #if DEBUG
            print("Recap CloudKit manifest has no payload IDs")
            #endif
            return []
        }
        let ids = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        #if DEBUG
        print("Recap CloudKit manifest fetched \(ids.count) payload IDs")
        #endif
        return ids
    }

    private func fetchPayloadRecords(payloadIDs: [String]) async throws -> [RecapSnapshotSyncPayload] {
        var allPayloads: [RecapSnapshotSyncPayload] = []
        for chunk in payloadIDs.chunked(into: fetchBatchSize) {
            let recordIDs = chunk.map { CKRecord.ID(recordName: $0, zoneID: Self.recordZoneID) }
            allPayloads.append(contentsOf: try await fetchPayloadRecords(recordIDs: recordIDs))
        }
        return allPayloads
    }

    private func fetchPayloadRecords(recordIDs: [CKRecord.ID]) async throws -> [RecapSnapshotSyncPayload] {
        try await withCheckedThrowingContinuation { continuation in
            let payloads = PayloadAccumulator()
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            operation.desiredKeys = [Field.capturedAt, Field.counterSignature, Field.payload]
            operation.perRecordResultBlock = { _, result in
                switch result {
                case .success(let record):
                    guard let payload = Self.payload(from: record) else {
                        return
                    }
                    payloads.append(payload)
                case .failure:
                    return
                }
            }
            operation.fetchRecordsResultBlock = { result in
                continuation.resume(with: result.map { payloads.values })
            }
            operation.qualityOfService = .utility
            database.add(operation)
        }
    }

    private func fetchRecord(withID recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let record {
                    continuation.resume(returning: record)
                } else {
                    continuation.resume(throwing: CKError(.unknownItem))
                }
            }
        }
    }

    private func modify(recordsToSave records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            operation.qualityOfService = .utility
            let errors = CloudKitRecordSaveErrors()
            operation.perRecordSaveBlock = { recordID, result in
                if case .failure(let error) = result {
                    errors.append(recordID: recordID, error: error)
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let error = errors.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private func saveManifest(payloadIDs: [String]) async throws {
        let recordID = CKRecord.ID(recordName: manifestRecordName, zoneID: Self.recordZoneID)
        let record = CKRecord(recordType: manifestRecordType, recordID: recordID)
        record[Field.payloadIDs] = try JSONEncoder().encode(payloadIDs) as NSData
        try await modify(recordsToSave: [record])
        #if DEBUG
        print("Recap CloudKit manifest saved \(payloadIDs.count) payload IDs")
        #endif
    }

    private func saveRecordZoneIfNeeded() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let zone = CKRecordZone(zoneID: Self.recordZoneID)
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            operation.qualityOfService = .utility
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    if Self.isZoneAlreadyExistsError(error) {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            database.add(operation)
        }
    }

    private static func payload(from record: CKRecord) -> RecapSnapshotSyncPayload? {
        let capturedAt = (record[Field.capturedAt] as? Date) ?? (record[Field.capturedAt] as? NSDate).map { $0 as Date }
        let data = (record[Field.payload] as? Data) ?? (record[Field.payload] as? NSData).map { $0 as Data }

        guard let capturedAt,
              let counterSignature = record[Field.counterSignature] as? String,
              let data else {
            return nil
        }

        return RecapSnapshotSyncPayload(
            id: record.recordID.recordName,
            capturedAt: capturedAt,
            counterSignature: counterSignature,
            encodedSnapshot: data
        )
    }

    private static func mergedPayloads(_ payloads: [RecapSnapshotSyncPayload]) -> [RecapSnapshotSyncPayload] {
        var payloadsByID: [String: RecapSnapshotSyncPayload] = [:]
        for payload in payloads {
            payloadsByID[payload.id] = payload
        }
        return Array(payloadsByID.values)
    }

    static func manifestPayloadIDs(for payloads: [RecapSnapshotSyncPayload]) -> [String] {
        var manifestPayloadIDs = OrderedUniqueStrings()
        manifestPayloadIDs.append(contentsOf: payloads.map(\.id))
        return manifestPayloadIDs.values
    }

    static func resolvedFetchedPayloads(
        manifestPayloadIDs: [String],
        manifestPayloads: [RecapSnapshotSyncPayload],
        zonePayloads: [RecapSnapshotSyncPayload]
    ) -> [RecapSnapshotSyncPayload] {
        let sourcePayloads = manifestPayloadIDs.isEmpty ? zonePayloads : manifestPayloads
        return Self.mergedPayloads(sourcePayloads)
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private static func isMissingZoneError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .zoneNotFound || ckError.code == .unknownItem {
            return true
        }
        return ckError.partialErrorsByItemID?.values.contains { isMissingZoneError($0) } == true
    }

    private static func isMissingManifestError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .unknownItem {
            return true
        }
        return ckError.partialErrorsByItemID?.values.contains { isMissingManifestError($0) } == true
    }

    private static func isZoneAlreadyExistsError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .serverRecordChanged || ckError.partialErrorsByItemID?.values.contains {
            isZoneAlreadyExistsError($0)
        } == true
    }
}

private final class PayloadAccumulator {
    private let lock = NSLock()
    private var storage: [RecapSnapshotSyncPayload] = []

    var values: [RecapSnapshotSyncPayload] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ payload: RecapSnapshotSyncPayload) {
        lock.lock()
        storage.append(payload)
        lock.unlock()
    }
}

private final class CloudKitRecordSaveErrors {
    private let lock = NSLock()
    private var failures: [(CKRecord.ID, Error)] = []

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        guard !failures.isEmpty else { return nil }
        return CloudKitPartialRecordSaveError(failures: failures)
    }

    func append(recordID: CKRecord.ID, error: Error) {
        lock.lock()
        failures.append((recordID, error))
        lock.unlock()
    }
}

private struct CloudKitPartialRecordSaveError: LocalizedError {
    let failures: [(CKRecord.ID, Error)]

    var errorDescription: String? {
        guard let first = failures.first else {
            return "CloudKit record save failed."
        }
        return "CloudKit failed to save \(failures.count) recap snapshot record(s). First failure \(first.0.recordName): \(first.1)"
    }
}

private struct OrderedUniqueStrings {
    private var seen = Set<String>()
    private(set) var values: [String] = []

    mutating func append(contentsOf strings: [String]) {
        for string in strings where seen.insert(string).inserted {
            values.append(string)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
