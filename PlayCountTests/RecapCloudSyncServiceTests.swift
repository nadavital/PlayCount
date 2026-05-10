import XCTest
import CloudKit
@testable import PlayCount

final class RecapCloudSyncServiceTests: XCTestCase {
    func testSyncMergesRemoteSnapshotsAndUploadsMergedLocalPayloads() async {
        let remoteStore = makeStore(named: "remote")
        let localStore = makeStore(named: "local")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let remoteDate = date(year: 2026, month: 5, day: 3)
        let localDate = date(year: 2026, month: 4, day: 29)

        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 1)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 5)],
            at: remoteDate,
            reason: .foreground
        )
        _ = localStore.record(
            songs: [song(id: 2, title: "Local", playCount: 2)],
            at: localDate,
            reason: .manualRefresh
        )

        let client = FakeRecapCloudSyncClient(remotePayloads: remoteStore.syncPayloads())
        let service = RecapCloudSyncService(client: client)

        let didMerge = await service.sync(snapshotStore: localStore)

        XCTAssertTrue(didMerge)
        XCTAssertEqual(localStore.syncPayloads().count, 3)
        XCTAssertEqual(client.savedPayloads.count, 1)
        XCTAssertEqual(localStore.recap(forMonthContaining: remoteDate).totalPlayDelta, 4)
    }

    func testSyncCanMergeRemoteWithoutUploadingLocalSnapshots() async {
        let remoteStore = makeStore(named: "remote-read-only")
        let localStore = makeStore(named: "local-read-only")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let remoteDate = date(year: 2026, month: 5, day: 3)

        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 1)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 5)],
            at: remoteDate,
            reason: .foreground
        )

        let client = FakeRecapCloudSyncClient(remotePayloads: remoteStore.syncPayloads())
        let service = RecapCloudSyncService(client: client, uploadsEnabled: false)

        let didMerge = await service.sync(snapshotStore: localStore)

        XCTAssertTrue(didMerge)
        XCTAssertTrue(client.savedPayloads.isEmpty)
        XCTAssertEqual(localStore.recap(forMonthContaining: remoteDate).totalPlayDelta, 4)
    }

    func testSyncUploadsLocalPayloadsBeforeMergingRemoteSnapshots() async {
        let remoteStore = makeStore(named: "remote-premerge")
        let localStore = makeStore(named: "local-premerge")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let localDate = date(year: 2026, month: 5, day: 3)
        let remoteDate = date(year: 2026, month: 5, day: 5)

        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 1)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 9)],
            at: remoteDate,
            reason: .foreground
        )
        _ = localStore.record(
            songs: [song(id: 2, title: "Local", playCount: 2)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = localStore.record(
            songs: [song(id: 2, title: "Local", playCount: 5)],
            at: localDate,
            reason: .foreground
        )
        let originalLocalPayloads = localStore.localSyncPayloads()

        let client = FakeRecapCloudSyncClient(remotePayloads: remoteStore.syncPayloads())
        let service = RecapCloudSyncService(client: client)

        _ = await service.sync(snapshotStore: localStore)

        XCTAssertEqual(client.savedPayloadCalls.first, originalLocalPayloads)
    }

    func testSyncDoesNothingWhenICloudIsUnavailable() async {
        let store = makeStore(named: "unavailable")
        _ = store.record(
            songs: [song(id: 1, title: "Local", playCount: 1)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .manualRefresh
        )

        let client = FakeRecapCloudSyncClient(isAvailable: false, remotePayloads: [])
        let service = RecapCloudSyncService(client: client)

        let didMerge = await service.sync(snapshotStore: store)

        XCTAssertFalse(didMerge)
        XCTAssertTrue(client.savedPayloads.isEmpty)
    }

    func testSyncTreatsMissingCloudKitRecordTypeAsEmptyRemoteStore() async {
        let store = makeStore(named: "empty-cloudkit")
        _ = store.record(
            songs: [song(id: 1, title: "Local", playCount: 3)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .manualRefresh
        )

        let client = FakeRecapCloudSyncClient(
            remotePayloads: [],
            fetchError: CKError(.unknownItem)
        )
        let service = RecapCloudSyncService(client: client)

        let didMerge = await service.sync(snapshotStore: store)

        XCTAssertFalse(didMerge)
        XCTAssertEqual(client.savedPayloads.count, 1)
    }

    func testSyncDoesNotUploadWhenFetchFailsForUnexpectedReason() async {
        let store = makeStore(named: "fetch-error")
        _ = store.record(
            songs: [song(id: 1, title: "Local", playCount: 3)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .manualRefresh
        )

        let client = FakeRecapCloudSyncClient(
            remotePayloads: [],
            fetchError: CKError(.networkFailure)
        )
        let service = RecapCloudSyncService(client: client)

        let didMerge = await service.sync(snapshotStore: store)

        XCTAssertFalse(didMerge)
        XCTAssertTrue(client.savedPayloads.isEmpty)
    }

    func testManifestPayloadIDsDescribeCurrentUploadSetOnly() {
        let payloads = [
            payload(id: "current-a"),
            payload(id: "current-b"),
            payload(id: "current-a")
        ]

        XCTAssertEqual(
            CloudKitRecapSyncClient.manifestPayloadIDs(for: payloads),
            ["current-a", "current-b"]
        )
    }

    func testResolvedFetchedPayloadsUseManifestAsSourceOfTruth() {
        let manifestPayload = payload(id: "manifest-current")
        let staleZonePayload = payload(id: "stale-zone")

        XCTAssertEqual(
            CloudKitRecapSyncClient.resolvedFetchedPayloads(
                manifestPayloadIDs: [manifestPayload.id],
                manifestPayloads: [manifestPayload],
                zonePayloads: [staleZonePayload]
            ),
            [manifestPayload]
        )
    }

    func testResolvedFetchedPayloadsFallBackToZoneWhenManifestIsEmpty() {
        let zonePayload = payload(id: "zone-legacy")

        XCTAssertEqual(
            CloudKitRecapSyncClient.resolvedFetchedPayloads(
                manifestPayloadIDs: [],
                manifestPayloads: [],
                zonePayloads: [zonePayload]
            ),
            [zonePayload]
        )
    }

    private func makeStore(named name: String) -> MonthlyRecapSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountCloudTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        return MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: name
        )
    }

    private func song(id: UInt64, title: String, playCount: Int) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: "Artist",
            albumTitle: "Album",
            playCount: playCount,
            skipCount: 0,
            totalPlayDuration: TimeInterval(playCount * 180),
            playbackDuration: 180,
            lastPlayedDate: nil,
            dateAdded: nil,
            artwork: nil,
            albumPersistentID: id + 100,
            artistPersistentID: 20,
            trackNumber: 1
        )
    }

    private func payload(id: String) -> RecapSnapshotSyncPayload {
        RecapSnapshotSyncPayload(
            id: id,
            capturedAt: date(year: 2026, month: 5, day: 1),
            counterSignature: id,
            encodedSnapshot: Data(id.utf8)
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: 12
        ).date!
    }
}

private final class FakeRecapCloudSyncClient: RecapCloudSyncClient {
    private let available: Bool
    private let remotePayloads: [RecapSnapshotSyncPayload]
    private let fetchError: Error?
    private(set) var savedPayloads: [RecapSnapshotSyncPayload] = []
    private(set) var savedPayloadCalls: [[RecapSnapshotSyncPayload]] = []

    init(
        isAvailable: Bool = true,
        remotePayloads: [RecapSnapshotSyncPayload],
        fetchError: Error? = nil
    ) {
        available = isAvailable
        self.remotePayloads = remotePayloads
        self.fetchError = fetchError
    }

    func isAvailable() async -> Bool {
        available
    }

    func fetchSnapshotPayloads() async throws -> [RecapSnapshotSyncPayload] {
        if let fetchError {
            throw fetchError
        }
        return remotePayloads
    }

    func saveSnapshotPayloads(_ payloads: [RecapSnapshotSyncPayload]) async throws {
        savedPayloads = payloads
        savedPayloadCalls.append(payloads)
    }
}
