import CloudKit
import Foundation

protocol RecapCloudSyncClient {
    func isAvailable() async -> Bool
    func fetchSnapshotPayloads() async throws -> [RecapSnapshotSyncPayload]
    func saveSnapshotPayloads(
        _ payloads: [RecapSnapshotSyncPayload],
        deletingPayloadIDs: [String],
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws
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
    func sync(
        snapshotStore: MonthlyRecapSnapshotStore,
        shouldContinue: @escaping @Sendable () async -> Bool = { true },
        shouldCommit: @escaping @Sendable () -> Bool = { true }
    ) async -> Bool {
        guard !Task.isCancelled, await shouldContinue() else { return false }
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
            guard !Task.isCancelled, await shouldContinue() else { return false }
            #if DEBUG
            print("Recap CloudKit sync fetched \(remotePayloads.count) remote payloads")
            #endif
            let didMergeRemote = snapshotStore.mergeSyncPayloads(
                remotePayloads,
                shouldCommit: shouldCommit
            )
            if uploadsEnabled {
                guard shouldCommit() else {
                    #if DEBUG
                    print("Recap CloudKit upload skipped: local commit gate closed")
                    #endif
                    return didMergeRemote
                }
                guard snapshotStore.isPersistenceHealthyForSync else {
                    #if DEBUG
                    print("Recap CloudKit upload skipped: local ledger is in read-only recovery mode")
                    #endif
                    return didMergeRemote
                }
                guard !Task.isCancelled, await shouldContinue() else { return false }
                let uploadPayloads = snapshotStore.syncPayloads(shouldCommit: shouldCommit)
                // Payload generation may itself compact/backfill and persist.
                // A failed save returns no payloads; never reinterpret that as
                // an authoritative request to delete the remote archive.
                guard snapshotStore.isPersistenceHealthyForSync else {
                    #if DEBUG
                    print("Recap CloudKit upload skipped: payload preparation did not persist")
                    #endif
                    return didMergeRemote
                }
                guard !Task.isCancelled, await shouldContinue() else { return false }
                let uploadPayloadIDs = Set(uploadPayloads.map(\.id))
                let deletingPayloadIDs = remotePayloads
                    .filter { !$0.isManifestArchiveOnly }
                    .map(\.id)
                    .filter { !uploadPayloadIDs.contains($0) }
                #if DEBUG
                print("Recap CloudKit sync saving \(uploadPayloads.count) compact payloads, deleting \(deletingPayloadIDs.count); didMergeRemote=\(didMergeRemote)")
                #endif
                guard !Task.isCancelled, await shouldContinue() else { return false }
                try await client.saveSnapshotPayloads(
                    uploadPayloads,
                    deletingPayloadIDs: deletingPayloadIDs,
                    shouldContinue: shouldContinue
                )
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
    static let manifestRecordSavePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged

    struct ManifestArchive: Equatable {
        let capturedAt: Date
        let reliabilityPolicyVersion: Int
        let encodedRecaps: Data?
        let encodedYearlyRecaps: Data?
        let encodedUnattributedIntervals: Data?
    }

    private enum Field {
        static let capturedAt = "capturedAt"
        static let counterSignature = "counterSignature"
        static let reliabilityPolicyVersion = "reliabilityPolicyVersion"
        static let archiveReliabilityPolicyVersion = "archiveReliabilityPolicyVersion"
        static let payload = "payload"
        static let payloadIDs = "payloadIDs"
        static let recapSummaries = "recapSummaries"
        static let yearlyRecapSummaries = "yearlyRecapSummaries"
    }

    private struct RecapEvidenceEnvelope: Codable {
        let yearlyRecapSummaries: Data?
        let unattributedIntervals: Data
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
    private let missingManifestPayloadIDs = LockedStringSet()

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
        missingManifestPayloadIDs.removeAll()
        do {
            try await saveRecordZoneIfNeeded()
            let manifest: (payloadIDs: [String], archive: ManifestArchive?)
            do {
                manifest = try await fetchManifest()
            } catch {
                guard Self.isMissingManifestError(error) else { throw error }
                // Existing users may have payload records written before the
                // manifest protocol. Discover those records before publishing a
                // first manifest so local state cannot make them unreachable.
                return try await fetchPayloadsFromZone(zoneID: Self.recordZoneID)
            }
            let payloadIDs = manifest.payloadIDs
            let manifestPayloads = payloadIDs.isEmpty ? [] : try await fetchPayloadRecords(payloadIDs: payloadIDs)
            if !payloadIDs.isEmpty {
                if manifestPayloads.isEmpty {
                    return Self.applyingManifestArchive(
                        manifest.archive,
                        to: []
                    )
                }
                return Self.applyingManifestArchive(
                    manifest.archive,
                    to: Self.resolvedFetchedPayloads(
                        manifestPayloadIDs: payloadIDs,
                        manifestPayloads: manifestPayloads,
                        zonePayloads: []
                    )
                )
            }

            // A present manifest is authoritative even when empty. Zone-scanning
            // here would resurrect records deliberately removed from it.
            return Self.applyingManifestArchive(manifest.archive, to: [])
        } catch {
            guard Self.isMissingZoneError(error) else { throw error }
            #if DEBUG
            print("Recap CloudKit sync zone unavailable: \(error)")
            #endif
            try await saveRecordZoneIfNeeded()
            return []
        }
    }

    func saveSnapshotPayloads(
        _ payloads: [RecapSnapshotSyncPayload],
        deletingPayloadIDs: [String],
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws {
        guard !payloads.isEmpty || !deletingPayloadIDs.isEmpty else { return }
        guard !Task.isCancelled, await shouldContinue() else { throw CancellationError() }
        try await saveRecordZoneIfNeeded()

        var seenPayloadIDs = Set<String>()
        let uniquePayloads = payloads.filter { payload in
            seenPayloadIDs.insert(payload.id).inserted
        }

        let records = uniquePayloads.filter { !$0.isManifestArchiveOnly }.map { payload in
            let recordID = CKRecord.ID(recordName: payload.id, zoneID: Self.recordZoneID)
            return Self.record(from: payload, recordID: recordID)
        }

        for chunk in records.chunked(into: saveBatchSize) {
            guard !Task.isCancelled, await shouldContinue() else { throw CancellationError() }
            try await modify(recordsToSave: chunk, recordIDsToDelete: [])
        }
        // Publish the replacement manifest before pruning old payload records. An
        // interrupted sync may leave harmless extras, but never dangling manifest IDs.
        guard !Task.isCancelled, await shouldContinue() else { throw CancellationError() }
        let manifestExclusions = Self.manifestExclusions(
            deletingPayloadIDs: deletingPayloadIDs,
            missingPayloadIDs: missingManifestPayloadIDs.values
        )
        try await saveManifest(
            payloadIDs: Self.manifestPayloadIDs(for: uniquePayloads.filter { !$0.isManifestArchiveOnly }),
            excludingPayloadIDs: manifestExclusions,
            archive: Self.localManifestArchive(from: uniquePayloads)
        )
        missingManifestPayloadIDs.removeAll()
        // The manifest is authoritative. Physical deletion is intentionally
        // deferred: deleting immediately after CAS can race a concurrent writer
        // that just re-added the same immutable payload ID, leaving a dangling
        // manifest reference. Orphaned records are invisible and recoverable;
        // a future tombstoned collector can remove them safely.
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
            configuration.desiredKeys = [
                Field.capturedAt,
                Field.counterSignature,
                Field.reliabilityPolicyVersion,
                Field.archiveReliabilityPolicyVersion,
                Field.payload,
                Field.recapSummaries,
                Field.yearlyRecapSummaries
            ]

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

    private func fetchManifest() async throws -> (payloadIDs: [String], archive: ManifestArchive?) {
        let recordID = CKRecord.ID(recordName: manifestRecordName, zoneID: Self.recordZoneID)
        let record = try await fetchRecord(withID: recordID)
        guard let data = Self.data(Field.payloadIDs, from: record) else {
            throw CocoaError(.coderReadCorrupt)
        }
        let ids = try Self.decodedManifestPayloadIDs(data)
        #if DEBUG
        print("Recap CloudKit manifest fetched \(ids.count) payload IDs")
        #endif
        return (ids, Self.manifestArchive(from: record))
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
            operation.desiredKeys = [
                Field.capturedAt,
                Field.counterSignature,
                Field.reliabilityPolicyVersion,
                Field.archiveReliabilityPolicyVersion,
                Field.payload,
                Field.recapSummaries,
                Field.yearlyRecapSummaries
            ]
            operation.perRecordResultBlock = { recordID, result in
                switch result {
                case .success(let record):
                    guard let payload = Self.payload(from: record) else {
                        return
                    }
                    payloads.append(payload)
                case .failure(let error):
                    if Self.isOnlyMissingRecordError(error) {
                        self.missingManifestPayloadIDs.insert(recordID.recordName)
                    }
                    return
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: payloads.values)
                case .failure(let error) where Self.isOnlyMissingRecordError(error):
                    // A prior interrupted cleanup can leave a dangling manifest ID.
                    // Return every surviving record so redundant recap summaries can
                    // repair the manifest on the next save.
                    continuation.resume(returning: payloads.values)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
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

    private func modify(
        recordsToSave records: [CKRecord],
        recordIDsToDelete: [CKRecord.ID] = [],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .allKeys
    ) async throws {
        let operation = CKModifyRecordsOperation(
            recordsToSave: records.isEmpty ? nil : records,
            recordIDsToDelete: recordIDsToDelete.isEmpty ? nil : recordIDsToDelete
        )
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.savePolicy = savePolicy
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
        } onCancel: {
            operation.cancel()
        }
    }

    private func saveManifest(
        payloadIDs: [String],
        excludingPayloadIDs: Set<String>,
        archive: ManifestArchive?
    ) async throws {
        try await saveManifest(
            payloadIDs: payloadIDs,
            excludingPayloadIDs: excludingPayloadIDs,
            archive: archive,
            attempt: 0
        )
    }

    private func saveManifest(
        payloadIDs: [String],
        excludingPayloadIDs: Set<String>,
        archive: ManifestArchive?,
        attempt: Int
    ) async throws {
        let recordID = CKRecord.ID(recordName: manifestRecordName, zoneID: Self.recordZoneID)
        let existingRecord: CKRecord?
        do {
            existingRecord = try await fetchRecord(withID: recordID)
        } catch {
            guard Self.isMissingManifestError(error) else { throw error }
            existingRecord = nil
        }

        let existingPayloadIDs = try existingRecord.map(Self.payloadIDs(from:)) ?? []
        let manifestPayloadIDs = Self.mergedManifestPayloadIDs(
            existingPayloadIDs: existingPayloadIDs,
            uploadPayloadIDs: payloadIDs,
            excludingPayloadIDs: excludingPayloadIDs
        )
        let record = existingRecord ?? CKRecord(recordType: manifestRecordType, recordID: recordID)
        record[Field.payloadIDs] = try JSONEncoder().encode(manifestPayloadIDs) as NSData
        if let preferredArchive = Self.preferredManifestArchive(
            existing: existingRecord.flatMap(Self.manifestArchive(from:)),
            local: archive
        ) {
            Self.apply(preferredArchive, to: record)
        }

        do {
            try await modify(
                recordsToSave: [record],
                // A record without a change tag is a conditional create. If two
                // devices race to publish the first manifest, the loser receives
                // serverRecordChanged and merges the winner rather than replacing it.
                savePolicy: Self.manifestRecordSavePolicy
            )
        } catch {
            guard attempt < 3, Self.isServerRecordChangedError(error) else { throw error }
            let latestRecord = try await fetchRecord(withID: recordID)
            let mergedPayloadIDs = Self.mergedManifestPayloadIDs(
                existingPayloadIDs: try Self.payloadIDs(from: latestRecord),
                uploadPayloadIDs: payloadIDs,
                excludingPayloadIDs: excludingPayloadIDs
            )
            try await saveManifest(
                payloadIDs: mergedPayloadIDs,
                excludingPayloadIDs: excludingPayloadIDs,
                archive: archive,
                attempt: attempt + 1
            )
            return
        }
        #if DEBUG
        print("Recap CloudKit manifest saved \(manifestPayloadIDs.count) payload IDs")
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

    static func record(from payload: RecapSnapshotSyncPayload, recordID: CKRecord.ID) -> CKRecord {
        let record = CKRecord(recordType: "RecapSnapshot", recordID: recordID)
        record[Field.capturedAt] = payload.capturedAt as NSDate
        record[Field.counterSignature] = payload.counterSignature as NSString
        if let reliabilityPolicyVersion = payload.reliabilityPolicyVersion {
            record[Field.reliabilityPolicyVersion] = reliabilityPolicyVersion as NSNumber
        }
        if let archiveReliabilityPolicyVersion = payload.archiveReliabilityPolicyVersion {
            record[Field.archiveReliabilityPolicyVersion] = archiveReliabilityPolicyVersion as NSNumber
        }
        record[Field.payload] = payload.encodedSnapshot as NSData
        if let encodedRecaps = payload.encodedRecaps {
            record[Field.recapSummaries] = encodedRecaps as NSData
        }
        if let encodedUnattributedIntervals = payload.encodedUnattributedIntervals,
           let envelope = try? JSONEncoder().encode(
               RecapEvidenceEnvelope(
                   yearlyRecapSummaries: payload.encodedYearlyRecaps,
                   unattributedIntervals: encodedUnattributedIntervals
               )
           ) {
            record[Field.yearlyRecapSummaries] = envelope as NSData
        } else if let encodedYearlyRecaps = payload.encodedYearlyRecaps {
            record[Field.yearlyRecapSummaries] = encodedYearlyRecaps as NSData
        }
        return record
    }

    static func payload(from record: CKRecord) -> RecapSnapshotSyncPayload? {
        let capturedAt = (record[Field.capturedAt] as? Date) ?? (record[Field.capturedAt] as? NSDate).map { $0 as Date }
        let data = (record[Field.payload] as? Data) ?? (record[Field.payload] as? NSData).map { $0 as Data }
        let recapData = (record[Field.recapSummaries] as? Data) ?? (record[Field.recapSummaries] as? NSData).map { $0 as Data }
        let storedYearlyRecapData = (record[Field.yearlyRecapSummaries] as? Data) ??
            (record[Field.yearlyRecapSummaries] as? NSData).map { $0 as Data }
        let evidenceEnvelope = storedYearlyRecapData.flatMap {
            try? JSONDecoder().decode(RecapEvidenceEnvelope.self, from: $0)
        }
        let yearlyRecapData = evidenceEnvelope?.yearlyRecapSummaries ?? storedYearlyRecapData
        let unattributedIntervalsData = evidenceEnvelope?.unattributedIntervals
        let reliabilityPolicyVersion = (record[Field.reliabilityPolicyVersion] as? NSNumber)?.intValue
        let archiveReliabilityPolicyVersion = (record[Field.archiveReliabilityPolicyVersion] as? NSNumber)?.intValue

        guard let capturedAt,
              let counterSignature = record[Field.counterSignature] as? String,
              let data else {
            return nil
        }

        return RecapSnapshotSyncPayload(
            id: record.recordID.recordName,
            capturedAt: capturedAt,
            counterSignature: counterSignature,
            reliabilityPolicyVersion: reliabilityPolicyVersion,
            archiveReliabilityPolicyVersion: archiveReliabilityPolicyVersion,
            encodedSnapshot: data,
            encodedRecaps: recapData,
            encodedYearlyRecaps: yearlyRecapData,
            encodedUnattributedIntervals: unattributedIntervalsData
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
        manifestPayloadIDs(from: payloads.map(\.id))
    }

    static func manifestPayloadIDs(from payloadIDs: [String]) -> [String] {
        var manifestPayloadIDs = OrderedUniqueStrings()
        manifestPayloadIDs.append(contentsOf: payloadIDs)
        return manifestPayloadIDs.values
    }

    static func mergedManifestPayloadIDs(existingPayloadIDs: [String], uploadPayloadIDs: [String]) -> [String] {
        mergedManifestPayloadIDs(
            existingPayloadIDs: existingPayloadIDs,
            uploadPayloadIDs: uploadPayloadIDs,
            excludingPayloadIDs: []
        )
    }

    static func mergedManifestPayloadIDs(
        existingPayloadIDs: [String],
        uploadPayloadIDs: [String],
        excludingPayloadIDs: Set<String>
    ) -> [String] {
        var manifestPayloadIDs = OrderedUniqueStrings()
        manifestPayloadIDs.append(contentsOf: existingPayloadIDs)
        manifestPayloadIDs.append(contentsOf: uploadPayloadIDs)
        return manifestPayloadIDs.values.filter { !excludingPayloadIDs.contains($0) }
    }

    static func manifestExclusions(
        deletingPayloadIDs: [String],
        missingPayloadIDs: Set<String>
    ) -> Set<String> {
        Set(deletingPayloadIDs).union(missingPayloadIDs)
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

    static func preferredManifestArchive(
        existing: ManifestArchive?,
        local: ManifestArchive?
    ) -> ManifestArchive? {
        guard let existing else { return local }
        guard let local else { return existing }
        let preferLocalFallback: Bool
        if local.reliabilityPolicyVersion != existing.reliabilityPolicyVersion {
            preferLocalFallback = local.reliabilityPolicyVersion > existing.reliabilityPolicyVersion
        } else {
            preferLocalFallback = local.capturedAt > existing.capturedAt
        }
        let evidence = MonthlyRecapSnapshotStore.mergedArchiveEvidence(
            existingRecaps: existing.encodedRecaps,
            existingYearlyRecaps: existing.encodedYearlyRecaps,
            existingUnattributedIntervals: existing.encodedUnattributedIntervals,
            localRecaps: local.encodedRecaps,
            localYearlyRecaps: local.encodedYearlyRecaps,
            localUnattributedIntervals: local.encodedUnattributedIntervals,
            preferLocalFallback: preferLocalFallback
        )
        return ManifestArchive(
            capturedAt: max(existing.capturedAt, local.capturedAt),
            reliabilityPolicyVersion: evidence.minimumReliabilityPolicyVersion ??
                (preferLocalFallback ? local.reliabilityPolicyVersion : existing.reliabilityPolicyVersion),
            encodedRecaps: evidence.encodedRecaps,
            encodedYearlyRecaps: evidence.encodedYearlyRecaps,
            encodedUnattributedIntervals: evidence.encodedUnattributedIntervals
        )
    }

    static func applyingManifestArchive(
        _ archive: ManifestArchive?,
        to payloads: [RecapSnapshotSyncPayload]
    ) -> [RecapSnapshotSyncPayload] {
        guard let archive else { return payloads }
        let payloadArchive = payloads.compactMap { payload -> ManifestArchive? in
            let validRecaps = MonthlyRecapSnapshotStore.isValidMonthlyArchiveEvidence(payload.encodedRecaps)
                ? payload.encodedRecaps : nil
            let validYearlyRecaps = MonthlyRecapSnapshotStore.isValidYearlyArchiveEvidence(payload.encodedYearlyRecaps)
                ? payload.encodedYearlyRecaps : nil
            let validIntervals = MonthlyRecapSnapshotStore.isValidUnattributedArchiveEvidence(
                payload.encodedUnattributedIntervals
            ) ? payload.encodedUnattributedIntervals : nil
            guard validRecaps != nil || validYearlyRecaps != nil || validIntervals != nil else {
                return nil
            }
            return ManifestArchive(
                capturedAt: payload.capturedAt,
                reliabilityPolicyVersion: payload.archiveReliabilityPolicyVersion ??
                    payload.reliabilityPolicyVersion ?? 0,
                encodedRecaps: validRecaps,
                encodedYearlyRecaps: validYearlyRecaps,
                encodedUnattributedIntervals: validIntervals
            )
        }.reduce(nil) { accumulated, payloadArchive in
            preferredManifestArchive(existing: accumulated, local: payloadArchive)
        }
        let resolvedArchive = preferredManifestArchive(existing: payloadArchive, local: archive) ?? archive
        guard let latest = payloads.indices.max(by: {
            payloads[$0].capturedAt < payloads[$1].capturedAt
        }) else {
            return [RecapSnapshotSyncPayload(
                id: RecapSnapshotSyncPayload.manifestArchiveOnlyID,
                capturedAt: resolvedArchive.capturedAt,
                counterSignature: "",
                reliabilityPolicyVersion: nil,
                archiveReliabilityPolicyVersion: resolvedArchive.reliabilityPolicyVersion,
                encodedSnapshot: Data(),
                encodedRecaps: resolvedArchive.encodedRecaps,
                encodedYearlyRecaps: resolvedArchive.encodedYearlyRecaps,
                encodedUnattributedIntervals: resolvedArchive.encodedUnattributedIntervals
            )]
        }
        return payloads.indices.map { index in
            let payload = payloads[index]
            guard index == latest else {
                return RecapSnapshotSyncPayload(
                    id: payload.id,
                    capturedAt: payload.capturedAt,
                    counterSignature: payload.counterSignature,
                    reliabilityPolicyVersion: payload.reliabilityPolicyVersion,
                    archiveReliabilityPolicyVersion: nil,
                    encodedSnapshot: payload.encodedSnapshot
                )
            }
            return RecapSnapshotSyncPayload(
                id: payload.id,
                capturedAt: payload.capturedAt,
                counterSignature: payload.counterSignature,
                // Archive policy describes only the durable recap evidence. It
                // must never promote an older raw snapshot through the current
                // raw-counter admission gate.
                reliabilityPolicyVersion: payload.reliabilityPolicyVersion,
                archiveReliabilityPolicyVersion: resolvedArchive.reliabilityPolicyVersion,
                encodedSnapshot: payload.encodedSnapshot,
                encodedRecaps: resolvedArchive.encodedRecaps,
                encodedYearlyRecaps: resolvedArchive.encodedYearlyRecaps,
                encodedUnattributedIntervals: resolvedArchive.encodedUnattributedIntervals
            )
        }
    }

    private static func localManifestArchive(
        from payloads: [RecapSnapshotSyncPayload]
    ) -> ManifestArchive? {
        payloads.filter {
            $0.encodedRecaps != nil || $0.encodedYearlyRecaps != nil || $0.encodedUnattributedIntervals != nil
        }.max { $0.capturedAt < $1.capturedAt }.map {
            ManifestArchive(
                capturedAt: $0.capturedAt,
                reliabilityPolicyVersion: $0.archiveReliabilityPolicyVersion ??
                    $0.reliabilityPolicyVersion ?? 0,
                encodedRecaps: $0.encodedRecaps,
                encodedYearlyRecaps: $0.encodedYearlyRecaps,
                encodedUnattributedIntervals: $0.encodedUnattributedIntervals
            )
        }
    }

    private static func manifestArchive(from record: CKRecord) -> ManifestArchive? {
        guard let capturedAt = (record[Field.capturedAt] as? Date) ??
                (record[Field.capturedAt] as? NSDate).map({ $0 as Date }) else {
            return nil
        }
        let policy = (record[Field.archiveReliabilityPolicyVersion] as? NSNumber)?.intValue ??
            (record[Field.reliabilityPolicyVersion] as? NSNumber)?.intValue ?? 0
        let storedYearlyData = data(Field.yearlyRecapSummaries, from: record)
        let envelope = storedYearlyData.flatMap { try? JSONDecoder().decode(RecapEvidenceEnvelope.self, from: $0) }
        let encodedRecaps = data(Field.recapSummaries, from: record)
        let encodedYearlyRecaps = envelope?.yearlyRecapSummaries ?? storedYearlyData
        let encodedUnattributedIntervals = envelope?.unattributedIntervals
        let validRecaps = MonthlyRecapSnapshotStore.isValidMonthlyArchiveEvidence(encodedRecaps)
            ? encodedRecaps : nil
        let validYearlyRecaps = MonthlyRecapSnapshotStore.isValidYearlyArchiveEvidence(encodedYearlyRecaps)
            ? encodedYearlyRecaps : nil
        let validIntervals = MonthlyRecapSnapshotStore.isValidUnattributedArchiveEvidence(encodedUnattributedIntervals)
            ? encodedUnattributedIntervals : nil
        guard validRecaps != nil || validYearlyRecaps != nil || validIntervals != nil else {
            return nil
        }
        return ManifestArchive(
            capturedAt: capturedAt,
            reliabilityPolicyVersion: policy,
            encodedRecaps: validRecaps,
            encodedYearlyRecaps: validYearlyRecaps,
            encodedUnattributedIntervals: validIntervals
        )
    }

    private static func apply(_ archive: ManifestArchive, to record: CKRecord) {
        record[Field.capturedAt] = archive.capturedAt as NSDate
        record[Field.archiveReliabilityPolicyVersion] = archive.reliabilityPolicyVersion as NSNumber
        if let encodedRecaps = archive.encodedRecaps {
            record[Field.recapSummaries] = encodedRecaps as NSData
        } else {
            record[Field.recapSummaries] = nil
        }
        if let encodedUnattributedIntervals = archive.encodedUnattributedIntervals,
           let envelope = try? JSONEncoder().encode(
               RecapEvidenceEnvelope(
                   yearlyRecapSummaries: archive.encodedYearlyRecaps,
                   unattributedIntervals: encodedUnattributedIntervals
               )
           ) {
            record[Field.yearlyRecapSummaries] = envelope as NSData
        } else {
            if let encodedYearlyRecaps = archive.encodedYearlyRecaps {
                record[Field.yearlyRecapSummaries] = encodedYearlyRecaps as NSData
            } else {
                record[Field.yearlyRecapSummaries] = nil
            }
        }
    }

    private static func data(_ key: String, from record: CKRecord) -> Data? {
        (record[key] as? Data) ?? (record[key] as? NSData).map { $0 as Data }
    }

    private static func isMissingZoneError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .zoneNotFound || ckError.code == .unknownItem {
            return true
        }
        return ckError.partialErrorsByItemID?.values.contains { isMissingZoneError($0) } == true
    }

    private static func isServerRecordChangedError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .serverRecordChanged {
            return true
        }
        return ckError.partialErrorsByItemID?.values.contains { isServerRecordChangedError($0) } == true
    }

    static func decodedManifestPayloadIDs(_ data: Data) throws -> [String] {
        try JSONDecoder().decode([String].self, from: data)
    }

    private static func payloadIDs(from record: CKRecord) throws -> [String] {
        guard let data = (record[Field.payloadIDs] as? Data) ?? (record[Field.payloadIDs] as? NSData).map({ $0 as Data }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return try decodedManifestPayloadIDs(data)
    }

    private static func isMissingManifestError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .unknownItem {
            return true
        }
        return ckError.partialErrorsByItemID?.values.contains { isMissingManifestError($0) } == true
    }

    static func isOnlyMissingRecordError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .unknownItem {
            return true
        }
        guard ckError.code == .partialFailure,
              let partialErrors = ckError.partialErrorsByItemID,
              !partialErrors.isEmpty else {
            return false
        }
        return partialErrors.values.allSatisfy(isOnlyMissingRecordError)
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

private final class LockedStringSet: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String> = []

    var values: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func insert(_ value: String) {
        lock.lock()
        storage.insert(value)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
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
