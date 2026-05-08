import CloudKit
import Foundation

protocol RecapCloudSyncClient {
    func isAvailable() async -> Bool
    func fetchSnapshotPayloads() async throws -> [RecapSnapshotSyncPayload]
    func saveSnapshotPayloads(_ payloads: [RecapSnapshotSyncPayload]) async throws
}

final class RecapCloudSyncService {
    private let client: RecapCloudSyncClient

    init(client: RecapCloudSyncClient) {
        self.client = client
    }

    static func live() -> RecapCloudSyncService {
        RecapCloudSyncService(client: CloudKitRecapSyncClient())
    }

    @discardableResult
    func sync(snapshotStore: MonthlyRecapSnapshotStore) async -> Bool {
        guard await client.isAvailable() else { return false }

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
            let didMergeRemote = snapshotStore.mergeSyncPayloads(remotePayloads)
            let localPayloads = snapshotStore.syncPayloads()
            try await client.saveSnapshotPayloads(localPayloads)
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
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "RecapSnapshot"

    init(container: CKContainer = .default()) {
        self.container = container
        database = container.privateCloudDatabase
    }

    func isAvailable() async -> Bool {
        await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
    }

    func fetchSnapshotPayloads() async throws -> [RecapSnapshotSyncPayload] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: Field.capturedAt, ascending: true)]
        return try await fetchPayloads(query: query)
    }

    func saveSnapshotPayloads(_ payloads: [RecapSnapshotSyncPayload]) async throws {
        guard !payloads.isEmpty else { return }

        let records = payloads.map { payload in
            let recordID = CKRecord.ID(recordName: payload.id)
            let record = CKRecord(recordType: recordType, recordID: recordID)
            record[Field.capturedAt] = payload.capturedAt as NSDate
            record[Field.counterSignature] = payload.counterSignature as NSString
            record[Field.payload] = payload.encodedSnapshot as NSData
            return record
        }

        for chunk in records.chunked(into: 100) {
            try await modify(recordsToSave: chunk)
        }
    }

    private func fetchPayloads(query: CKQuery) async throws -> [RecapSnapshotSyncPayload] {
        try await withCheckedThrowingContinuation { continuation in
            let payloads = PayloadAccumulator()
            fetchPayloads(query: query, cursor: nil, into: payloads) { result in
                continuation.resume(with: result.map { payloads.values })
            }
        }
    }

    private func fetchPayloads(
        query: CKQuery,
        cursor: CKQueryOperation.Cursor?,
        into payloads: PayloadAccumulator,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let operation: CKQueryOperation
        if let cursor {
            operation = CKQueryOperation(cursor: cursor)
        } else {
            operation = CKQueryOperation(query: query)
        }

        operation.desiredKeys = [Field.capturedAt, Field.counterSignature, Field.payload]
        operation.resultsLimit = CKQueryOperation.maximumResults
        operation.recordMatchedBlock = { _, result in
            guard case .success(let record) = result,
                  let payload = Self.payload(from: record) else {
                return
            }
            payloads.append(payload)
        }
        operation.queryResultBlock = { [weak self] result in
            switch result {
            case .success(let nextCursor):
                if let nextCursor, let self {
                    self.fetchPayloads(query: query, cursor: nextCursor, into: payloads, completion: completion)
                } else {
                    completion(.success(()))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }

        operation.qualityOfService = .utility
        database.add(operation)
    }

    private func modify(recordsToSave records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .allKeys
            operation.qualityOfService = .utility
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
