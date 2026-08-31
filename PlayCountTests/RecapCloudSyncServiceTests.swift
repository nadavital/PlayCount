import XCTest
import CloudKit
@testable import PlayCount

final class RecapCloudSyncServiceTests: XCTestCase {
    func testSyncNeverUploadsOrDeletesWhenLocalLedgerIsUnreadable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountCloudCorruptLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDate = date(year: 2026, month: 5, day: 1)
        do {
            let initial = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: Calendar(identifier: .gregorian),
                deviceIdentifier: "corrupt-local"
            )
            _ = initial.record(
                songs: [song(id: 1, title: "Preserved", playCount: 10)],
                at: localDate,
                reason: .foreground
            )
        }
        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        try Data("broken".utf8).write(to: ledgerURL, options: .atomic)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-shm"))
        let local = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "corrupt-local"
        )
        let remote = makeStore(named: "corrupt-ledger-remote")
        _ = remote.record(
            songs: [song(id: 2, title: "Remote", playCount: 20)],
            at: localDate,
            reason: .foreground
        )
        let client = FakeRecapCloudSyncClient(remotePayloads: remote.syncPayloads())

        _ = await RecapCloudSyncService(client: client).sync(snapshotStore: local)

        XCTAssertTrue(client.savedPayloadCalls.isEmpty)
        XCTAssertTrue(client.deletedPayloadIDs.isEmpty)
    }

    func testTransientReadFailureCannotReopenPruningGateAfterSkippedRemoteMergeSave() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountCloudReadRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let localDate = date(year: 2026, month: 5, day: 1)
        do {
            let initial = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "read-retry-local"
            )
            _ = initial.record(
                songs: [song(id: 1, title: "Local", playCount: 10)],
                at: localDate,
                reason: .foreground
            )
        }
        let remote = makeStore(named: "read-retry-remote")
        _ = remote.record(
            songs: [song(id: 2, title: "Remote Only", playCount: 20)],
            at: date(year: 2026, month: 5, day: 2),
            reason: .foreground
        )
        let readGate = FailOncePersistenceReadGate()
        let local = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "read-retry-local",
            persistenceReadAllowed: { readGate.isAllowed }
        )
        let client = FakeRecapCloudSyncClient(remotePayloads: remote.syncPayloads())

        let didMerge = await RecapCloudSyncService(client: client).sync(snapshotStore: local)
        XCTAssertFalse(didMerge)
        XCTAssertTrue(client.savedPayloadCalls.isEmpty)
        XCTAssertTrue(client.deletedPayloadIDs.isEmpty)
        XCTAssertFalse(local.isPersistenceHealthyForSync)
    }

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
        XCTAssertEqual(client.savedPayloads.count, 3)
        XCTAssertEqual(client.savedPayloads.filter { $0.encodedRecaps != nil }.count, min(2, client.savedPayloads.count))
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

    func testSyncStopsBeforeMergingWhenContinuationGateClosesAfterFetch() async {
        let remoteStore = makeStore(named: "remote-cancelled")
        let localStore = makeStore(named: "local-cancelled")
        let remoteDate = date(year: 2026, month: 5, day: 3)
        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 5)],
            at: remoteDate,
            reason: .foreground
        )

        let client = FakeRecapCloudSyncClient(remotePayloads: remoteStore.syncPayloads())
        let gate = SyncContinuationGate(allowedChecks: 1)
        let didMerge = await RecapCloudSyncService(client: client).sync(
            snapshotStore: localStore,
            shouldContinue: { await gate.shouldContinue() }
        )

        XCTAssertFalse(didMerge)
        XCTAssertTrue(localStore.syncPayloads().isEmpty)
        XCTAssertTrue(client.savedPayloads.isEmpty)
    }

    func testSyncNeverDeletesRemotePayloadsWhenCommitGateCloses() async {
        let remoteStore = makeStore(named: "remote-commit-gated")
        let localStore = makeStore(named: "local-commit-gated")
        _ = remoteStore.record(
            songs: [song(id: 1, title: "Remote", playCount: 5)],
            at: date(year: 2026, month: 5, day: 3),
            reason: .foreground
        )
        let client = FakeRecapCloudSyncClient(remotePayloads: remoteStore.syncPayloads())

        let didMerge = await RecapCloudSyncService(client: client).sync(
            snapshotStore: localStore,
            shouldCommit: { false }
        )

        XCTAssertFalse(didMerge)
        XCTAssertTrue(client.savedPayloadCalls.isEmpty)
        XCTAssertTrue(client.deletedPayloadIDs.isEmpty)
    }

    func testPayloadPreparationSaveFailureNeverDeletesRemoteArchive() async {
        let gate = CloudPersistenceGate()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountCloudSaveFailure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "payload-save-failure",
            persistenceWriteAllowed: { gate.isAllowed }
        )
        _ = store.record(
            songs: [song(id: 1, title: "Old", playCount: 10)],
            at: date(year: 2024, month: 1, day: 1),
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Old", playCount: 14)],
            at: date(year: 2024, month: 1, day: 3),
            reason: .foreground
        )
        gate.isAllowed = false
        let client = FakeRecapCloudSyncClient(remotePayloads: [payload(id: "remote-only")])

        let didMerge = await RecapCloudSyncService(client: client).sync(snapshotStore: store)

        XCTAssertFalse(didMerge)
        XCTAssertTrue(client.savedPayloadCalls.isEmpty)
        XCTAssertTrue(client.deletedPayloadIDs.isEmpty)
        XCTAssertFalse(store.isPersistenceHealthyForSync)
    }

    func testBothDevicesCanUploadWithoutReplacingManifestWithLocalOnlySnapshots() async {
        let phoneStore = makeStore(named: "phone-uploader")
        let iPadStore = makeStore(named: "ipad-uploader")
        let baselineDate = date(year: 2026, month: 5, day: 5)
        let phoneLatestDate = date(year: 2026, month: 5, day: 9)
        let iPadLatestDate = date(year: 2026, month: 5, day: 10)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone", playCount: 100)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone", playCount: 140)],
            at: phoneLatestDate,
            reason: .foreground
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "iPad", playCount: 100)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "iPad", playCount: 165)],
            at: iPadLatestDate,
            reason: .foreground
        )

        let phoneInitialClient = FakeRecapCloudSyncClient(remotePayloads: [])
        _ = await RecapCloudSyncService(client: phoneInitialClient).sync(snapshotStore: phoneStore)
        XCTAssertEqual(phoneInitialClient.savedPayloads.count, 2)

        let iPadClient = FakeRecapCloudSyncClient(remotePayloads: phoneInitialClient.savedPayloads)
        _ = await RecapCloudSyncService(client: iPadClient).sync(snapshotStore: iPadStore)
        XCTAssertEqual(iPadClient.savedPayloads.count, 4)
        XCTAssertEqual(iPadClient.savedPayloads.filter { $0.encodedRecaps != nil }.count, min(2, iPadClient.savedPayloads.count))

        let phoneSecondClient = FakeRecapCloudSyncClient(remotePayloads: iPadClient.savedPayloads)
        _ = await RecapCloudSyncService(client: phoneSecondClient).sync(snapshotStore: phoneStore)
        XCTAssertEqual(phoneSecondClient.savedPayloads.count, 4)

        XCTAssertEqual(
            phoneStore.recap(forMonthContaining: iPadLatestDate).totalPlayDelta,
            iPadStore.recap(forMonthContaining: iPadLatestDate).totalPlayDelta
        )
        XCTAssertEqual(phoneStore.recap(forMonthContaining: iPadLatestDate).totalPlayDelta, 65)
    }

    func testSyncUploadsMergedManifestPayloadsAfterMergingRemoteSnapshots() async {
        let remoteStore = makeStore(named: "remote-merged-manifest")
        let localStore = makeStore(named: "local-merged-manifest")
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

        let client = FakeRecapCloudSyncClient(remotePayloads: remoteStore.syncPayloads())
        let service = RecapCloudSyncService(client: client)

        _ = await service.sync(snapshotStore: localStore)

        XCTAssertEqual(client.savedPayloadCalls.count, 1)
        XCTAssertEqual(
            Set(client.savedPayloadCalls.first?.map(\.id) ?? []),
            Set((remoteStore.syncPayloads() + localStore.syncPayloads()).map(\.id))
        )
        XCTAssertEqual(client.savedPayloads.count, 4)
    }

    func testSyncPrunesRemotePayloadsThatLocalCompactionDropsAfterMerge() async {
        let fullSourceStore = makeStore(named: "full-remote-preserved")
        let trimmedSourceStore = makeStore(named: "trimmed-remote-preserved")
        let localStore = makeStore(named: "local-remote-preserved")
        let baselineDate = date(year: 2026, month: 5, day: 5)
        let baselineSongs = (0..<12).map { index in
            song(id: UInt64(100 + index), title: "Song \(index)", playCount: 20 - index)
        }
        let trimmedBaselineSongs = Array(baselineSongs.prefix(5))

        _ = fullSourceStore.record(
            songs: baselineSongs,
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = trimmedSourceStore.debugRecordLegacySnapshot(
            songs: trimmedBaselineSongs,
            at: baselineDate,
            reason: .manualRefresh,
            scannedSongCount: baselineSongs.count,
            aggregateSongs: baselineSongs
        )

        let remotePayloads = fullSourceStore.syncPayloads() + trimmedSourceStore.syncPayloads()
        let client = FakeRecapCloudSyncClient(remotePayloads: remotePayloads)

        _ = await RecapCloudSyncService(client: client).sync(snapshotStore: localStore)

        XCTAssertEqual(localStore.syncPayloads().count, 1)
        XCTAssertEqual(Set(client.savedPayloads.map(\.id)), Set(localStore.syncPayloads().map(\.id)))
        XCTAssertEqual(Set(client.deletedPayloadIDs), Set(remotePayloads.map(\.id)).subtracting(client.savedPayloads.map(\.id)))
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

    func testSyncTreatsMissingCloudKitZoneAsEmptyRemoteStore() async {
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

    func testMergedManifestPayloadIDsCanStillDescribeLegacyUnion() {
        XCTAssertEqual(
            CloudKitRecapSyncClient.mergedManifestPayloadIDs(
                existingPayloadIDs: ["older-a", "newer-phone", "older-a"],
                uploadPayloadIDs: ["older-a", "ipad-local"]
            ),
            ["older-a", "newer-phone", "ipad-local"]
        )
    }

    func testConflictManifestMergeKeepsConcurrentUploadsButExcludesPrunedRecords() {
        XCTAssertEqual(
            CloudKitRecapSyncClient.mergedManifestPayloadIDs(
                existingPayloadIDs: ["stale", "other-device-new"],
                uploadPayloadIDs: ["this-device-new"],
                excludingPayloadIDs: ["stale"]
            ),
            ["other-device-new", "this-device-new"]
        )
    }

    func testManifestMergePreservesOtherDeviceCommitThatArrivedBeforeManifestFetch() {
        XCTAssertEqual(
            CloudKitRecapSyncClient.mergedManifestPayloadIDs(
                existingPayloadIDs: ["remote-seen-at-sync-start", "other-device-just-committed"],
                uploadPayloadIDs: ["this-device-upload"],
                excludingPayloadIDs: ["remote-seen-at-sync-start"]
            ),
            ["other-device-just-committed", "this-device-upload"]
        )
    }

    func testManifestRepairExcludesDanglingMissingPayloadIDsAlongsidePrunedIDs() {
        XCTAssertEqual(
            CloudKitRecapSyncClient.manifestExclusions(
                deletingPayloadIDs: ["compacted-away"],
                missingPayloadIDs: ["dangling-record"]
            ),
            ["compacted-away", "dangling-record"]
        )
        XCTAssertEqual(
            CloudKitRecapSyncClient.mergedManifestPayloadIDs(
                existingPayloadIDs: ["survivor", "dangling-record", "compacted-away"],
                uploadPayloadIDs: ["new-local"],
                excludingPayloadIDs: CloudKitRecapSyncClient.manifestExclusions(
                    deletingPayloadIDs: ["compacted-away"],
                    missingPayloadIDs: ["dangling-record"]
                )
            ),
            ["survivor", "new-local"]
        )
    }

    func testConcurrentInitialManifestCreationUsesConflictDetection() {
        XCTAssertEqual(
            CloudKitRecapSyncClient.manifestRecordSavePolicy,
            .ifServerRecordUnchanged,
            "A second device creating the same initial manifest must conflict and merge, never overwrite the first manifest"
        )
    }

    func testManifestArchivePrefersCorrectedPolicyOverNewerStalePayloadSummary() {
        let stale = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: date(year: 2026, month: 8, day: 20),
            reliabilityPolicyVersion: 2,
            encodedRecaps: Data("inflated".utf8),
            encodedYearlyRecaps: nil,
            encodedUnattributedIntervals: nil
        )
        let corrected = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: date(year: 2026, month: 8, day: 10),
            reliabilityPolicyVersion: 3,
            encodedRecaps: Data("corrected-lower".utf8),
            encodedYearlyRecaps: nil,
            encodedUnattributedIntervals: nil
        )

        let correctedLocal = CloudKitRecapSyncClient.preferredManifestArchive(existing: stale, local: corrected)
        let correctedExisting = CloudKitRecapSyncClient.preferredManifestArchive(existing: corrected, local: stale)
        XCTAssertEqual(correctedLocal?.encodedRecaps, corrected.encodedRecaps)
        XCTAssertEqual(correctedExisting?.encodedRecaps, corrected.encodedRecaps)
        XCTAssertEqual(correctedLocal?.reliabilityPolicyVersion, 3)
        XCTAssertEqual(correctedExisting?.reliabilityPolicyVersion, 3)
        XCTAssertEqual(correctedLocal?.capturedAt, stale.capturedAt)
        XCTAssertEqual(correctedExisting?.capturedAt, stale.capturedAt)
    }

    func testManifestArchiveUsesLatestCaptureWithinSameReliabilityPolicy() {
        let earlier = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: date(year: 2026, month: 8, day: 10),
            reliabilityPolicyVersion: 3,
            encodedRecaps: Data("earlier".utf8),
            encodedYearlyRecaps: nil,
            encodedUnattributedIntervals: nil
        )
        let later = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: date(year: 2026, month: 8, day: 20),
            reliabilityPolicyVersion: 3,
            encodedRecaps: Data("later".utf8),
            encodedYearlyRecaps: nil,
            encodedUnattributedIntervals: nil
        )

        XCTAssertEqual(
            CloudKitRecapSyncClient.preferredManifestArchive(existing: earlier, local: later),
            later
        )
    }

    func testManifestArchiveOverridesMutablePayloadSummaryCopies() {
        let earlier = RecapSnapshotSyncPayload(
            id: "earlier",
            capturedAt: date(year: 2026, month: 8, day: 10),
            counterSignature: "earlier",
            reliabilityPolicyVersion: 2,
            encodedSnapshot: Data("snapshot-a".utf8),
            encodedRecaps: Data("stale-a".utf8)
        )
        let later = RecapSnapshotSyncPayload(
            id: "later",
            capturedAt: date(year: 2026, month: 8, day: 20),
            counterSignature: "later",
            reliabilityPolicyVersion: 2,
            encodedSnapshot: Data("snapshot-b".utf8),
            encodedRecaps: Data("stale-b".utf8)
        )
        let archive = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: later.capturedAt,
            reliabilityPolicyVersion: 3,
            encodedRecaps: Data("corrected".utf8),
            encodedYearlyRecaps: Data("year".utf8),
            encodedUnattributedIntervals: Data("gaps".utf8)
        )

        let resolved = CloudKitRecapSyncClient.applyingManifestArchive(archive, to: [earlier, later])
        XCTAssertNil(resolved[0].encodedRecaps)
        XCTAssertEqual(resolved[1].encodedRecaps, Data("corrected".utf8))
        XCTAssertEqual(resolved[1].encodedYearlyRecaps, Data("year".utf8))
        XCTAssertEqual(resolved[1].encodedUnattributedIntervals, Data("gaps".utf8))
        XCTAssertEqual(resolved[1].reliabilityPolicyVersion, 2)
        XCTAssertEqual(resolved[1].archiveReliabilityPolicyVersion, 3)
    }

    func testPartialManifestArchivePreservesComplementaryPayloadEvidence() throws {
        let source = makeStore(named: "partial-manifest-source")
        _ = source.record(
            songs: [song(id: 1, title: "May", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        _ = source.record(
            songs: [song(id: 1, title: "May", playCount: 14)],
            at: date(year: 2026, month: 5, day: 3),
            reason: .foreground
        )
        let sourcePayload = try XCTUnwrap(source.syncPayloads().first { $0.encodedRecaps != nil })
        let payload = RecapSnapshotSyncPayload(
            id: "raw-v2",
            capturedAt: sourcePayload.capturedAt,
            counterSignature: "raw-v2",
            reliabilityPolicyVersion: 2,
            archiveReliabilityPolicyVersion: 2,
            encodedSnapshot: Data("old-raw-snapshot".utf8),
            encodedRecaps: sourcePayload.encodedRecaps
        )
        let manifest = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: sourcePayload.capturedAt.addingTimeInterval(60),
            reliabilityPolicyVersion: 3,
            encodedRecaps: nil,
            encodedYearlyRecaps: sourcePayload.encodedYearlyRecaps,
            encodedUnattributedIntervals: nil
        )

        let resolved = try XCTUnwrap(
            CloudKitRecapSyncClient.applyingManifestArchive(manifest, to: [payload]).first
        )
        XCTAssertEqual(resolved.reliabilityPolicyVersion, 2)
        // The retained monthly archive now carries policy 4. A partial policy-3
        // manifest must not downgrade that complementary monthly evidence.
        XCTAssertEqual(resolved.archiveReliabilityPolicyVersion, sourcePayload.archiveReliabilityPolicyVersion)
        XCTAssertNotNil(resolved.encodedRecaps)
        XCTAssertNotNil(resolved.encodedYearlyRecaps)
    }

    func testEmptyManifestCanRestoreItsArchiveWithoutResurrectingZonePayloads() {
        let archive = CloudKitRecapSyncClient.ManifestArchive(
            capturedAt: date(year: 2026, month: 8, day: 20),
            reliabilityPolicyVersion: 3,
            encodedRecaps: Data("months".utf8),
            encodedYearlyRecaps: Data("years".utf8),
            encodedUnattributedIntervals: Data("gaps".utf8)
        )

        let restored = CloudKitRecapSyncClient.applyingManifestArchive(archive, to: [])
        XCTAssertEqual(restored.count, 1)
        XCTAssertTrue(restored[0].isManifestArchiveOnly)
        XCTAssertEqual(restored[0].encodedRecaps, Data("months".utf8))
        XCTAssertEqual(restored[0].encodedYearlyRecaps, Data("years".utf8))
        XCTAssertEqual(restored[0].encodedUnattributedIntervals, Data("gaps".utf8))
    }

    func testManifestArchiveMergesUniqueMonthsAcrossMixedPolicyDevices() throws {
        let older = makeStore(named: "archive-merge-older")
        let mixed = makeStore(named: "archive-merge-mixed")
        let target = makeStore(named: "archive-merge-target")

        _ = older.record(
            songs: [song(id: 1, title: "May", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        _ = older.record(
            songs: [song(id: 1, title: "May", playCount: 14)],
            at: date(year: 2026, month: 5, day: 3),
            reason: .foreground
        )

        let julySource = makeStore(named: "archive-merge-july-source")
        _ = julySource.record(
            songs: [song(id: 2, title: "July", playCount: 20)],
            at: date(year: 2026, month: 7, day: 1),
            reason: .foreground
        )
        let july = julySource.record(
            songs: [song(id: 2, title: "July", playCount: 25)],
            at: date(year: 2026, month: 7, day: 3),
            reason: .foreground
        )
        _ = mixed.record(
            songs: [song(id: 3, title: "August", playCount: 30)],
            at: date(year: 2026, month: 8, day: 1),
            reason: .foreground
        )
        _ = mixed.record(
            songs: [song(id: 3, title: "August", playCount: 36)],
            at: date(year: 2026, month: 8, day: 3),
            reason: .foreground
        )
        mixed.debugInstallSyncedRecapCandidates([(july, 2)])

        func archive(from store: MonthlyRecapSnapshotStore) throws -> CloudKitRecapSyncClient.ManifestArchive {
            let payload = try XCTUnwrap(store.syncPayloads().first { $0.encodedRecaps != nil })
            return CloudKitRecapSyncClient.ManifestArchive(
                capturedAt: payload.capturedAt,
                reliabilityPolicyVersion: payload.archiveReliabilityPolicyVersion ?? 0,
                encodedRecaps: payload.encodedRecaps,
                encodedYearlyRecaps: payload.encodedYearlyRecaps,
                encodedUnattributedIntervals: payload.encodedUnattributedIntervals
            )
        }

        let merged = try XCTUnwrap(CloudKitRecapSyncClient.preferredManifestArchive(
            existing: archive(from: older),
            local: archive(from: mixed)
        ))
        XCTAssertEqual(merged.reliabilityPolicyVersion, 2)
        XCTAssertTrue(target.mergeSyncPayloads(
            CloudKitRecapSyncClient.applyingManifestArchive(merged, to: []),
            now: date(year: 2026, month: 8, day: 4)
        ))
        XCTAssertEqual(target.recap(forMonthContaining: date(year: 2026, month: 5, day: 3)).totalPlayDelta, 4)
        XCTAssertEqual(target.recap(forMonthContaining: date(year: 2026, month: 7, day: 3)).totalPlayDelta, 5)
        XCTAssertEqual(target.recap(forMonthContaining: date(year: 2026, month: 8, day: 3)).totalPlayDelta, 6)
    }

    func testMissingManifestRecordErrorsAreRecoverableButNetworkErrorsAreNot() {
        let recordID = CKRecord.ID(
            recordName: "missing",
            zoneID: CKRecordZone.ID(zoneName: "test-zone", ownerName: CKCurrentUserDefaultName)
        )
        let partialMissing = CKError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [recordID: CKError(.unknownItem)]]
        )
        XCTAssertTrue(CloudKitRecapSyncClient.isOnlyMissingRecordError(partialMissing))
        XCTAssertFalse(CloudKitRecapSyncClient.isOnlyMissingRecordError(CKError(.networkFailure)))
    }

    func testMalformedManifestPayloadIDsFailClosedInsteadOfBecomingEmpty() {
        XCTAssertThrowsError(
            try CloudKitRecapSyncClient.decodedManifestPayloadIDs(Data("not-json".utf8))
        )
        XCTAssertThrowsError(
            try CloudKitRecapSyncClient.decodedManifestPayloadIDs(Data("{\"payloadIDs\":[]}".utf8))
        )
        XCTAssertEqual(
            try CloudKitRecapSyncClient.decodedManifestPayloadIDs(Data("[]".utf8)),
            []
        )
    }

    func testMalformedManifestArchiveEvidenceIsRejectedWithoutStrippingPayloadCopies() {
        XCTAssertFalse(MonthlyRecapSnapshotStore.isValidArchiveEvidence(
            encodedRecaps: Data("corrupt".utf8),
            encodedYearlyRecaps: nil,
            encodedUnattributedIntervals: nil
        ))
        let payloadWithValidCopy = RecapSnapshotSyncPayload(
            id: "payload",
            capturedAt: date(year: 2026, month: 8, day: 20),
            counterSignature: "payload",
            reliabilityPolicyVersion: 3,
            encodedSnapshot: Data("snapshot".utf8),
            encodedRecaps: Data("valid-copy-placeholder".utf8)
        )
        XCTAssertEqual(
            CloudKitRecapSyncClient.applyingManifestArchive(nil, to: [payloadWithValidCopy]),
            [payloadWithValidCopy]
        )
        XCTAssertFalse(MonthlyRecapSnapshotStore.isValidMonthlyArchiveEvidence(Data("corrupt".utf8)))
        XCTAssertTrue(MonthlyRecapSnapshotStore.isValidYearlyArchiveEvidence(nil))
        XCTAssertTrue(MonthlyRecapSnapshotStore.isValidUnattributedArchiveEvidence(nil))
    }

    func testYearOnlyArchiveSurvivesMergeWithoutMonthlyLedgers() throws {
        let source = makeStore(named: "year-only-source")
        let target = makeStore(named: "year-only-target")
        _ = source.record(
            songs: [song(id: 1, title: "Year", playCount: 10)],
            at: date(year: 2025, month: 5, day: 1),
            reason: .foreground
        )
        _ = source.record(
            songs: [song(id: 1, title: "Year", playCount: 14)],
            at: date(year: 2025, month: 5, day: 3),
            reason: .foreground
        )
        let sourcePayload = try XCTUnwrap(source.syncPayloads().first { $0.encodedYearlyRecaps != nil })
        let yearOnly = RecapSnapshotSyncPayload(
            id: RecapSnapshotSyncPayload.manifestArchiveOnlyID,
            capturedAt: sourcePayload.capturedAt,
            counterSignature: "",
            reliabilityPolicyVersion: 3,
            archiveReliabilityPolicyVersion: 3,
            encodedSnapshot: Data(),
            encodedYearlyRecaps: sourcePayload.encodedYearlyRecaps
        )

        XCTAssertTrue(target.mergeSyncPayloads([yearOnly], now: date(year: 2026, month: 8, day: 1)))
        XCTAssertEqual(target.syncedYearlyRecap(for: 2025)?.totalPlayDelta, 4)

        _ = target.record(
            songs: [song(id: 2, title: "Current", playCount: 20)],
            at: date(year: 2025, month: 8, day: 2),
            reason: .foreground
        )
        XCTAssertEqual(target.syncedYearlyRecap(for: 2025)?.totalPlayDelta, 4)
    }

    func testCurrentManifestPayloadIDsReplaceRemoteManifestEntries() {
        XCTAssertEqual(
            CloudKitRecapSyncClient.manifestPayloadIDs(from: ["current-a", "current-b", "current-a"]),
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

    func testCloudRecordRoundTripKeepsGapEvidenceOutsideNearLimitSnapshot() throws {
        let snapshotData = Data(repeating: 0x5A, count: 249_000)
        let intervalData = Data(repeating: 0xA5, count: 12_000)
        XCTAssertGreaterThan(snapshotData.count + intervalData.count, 250_000)
        let original = RecapSnapshotSyncPayload(
            id: "near-limit-gap-evidence",
            capturedAt: date(year: 2026, month: 8, day: 25),
            counterSignature: "near-limit",
            reliabilityPolicyVersion: 2,
            encodedSnapshot: snapshotData,
            encodedRecaps: Data("monthly".utf8),
            encodedYearlyRecaps: Data("yearly".utf8),
            encodedUnattributedIntervals: intervalData
        )
        let recordID = CKRecord.ID(
            recordName: original.id,
            zoneID: CKRecordZone.ID(zoneName: "test-zone", ownerName: CKCurrentUserDefaultName)
        )

        let record = CloudKitRecapSyncClient.record(from: original, recordID: recordID)
        let roundTripped = try XCTUnwrap(CloudKitRecapSyncClient.payload(from: record))

        XCTAssertEqual(roundTripped, original)
        XCTAssertEqual(roundTripped.encodedUnattributedIntervals, intervalData)
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
            albumArtist: "Artist",
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
    private(set) var deletedPayloadIDs: [String] = []

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

    func saveSnapshotPayloads(
        _ payloads: [RecapSnapshotSyncPayload],
        deletingPayloadIDs: [String],
        shouldContinue: @escaping @Sendable () async -> Bool
    ) async throws {
        guard await shouldContinue() else { throw CancellationError() }
        savedPayloads = payloads
        savedPayloadCalls.append(payloads)
        deletedPayloadIDs = deletingPayloadIDs
    }
}

private actor SyncContinuationGate {
    private var remainingAllowedChecks: Int

    init(allowedChecks: Int) {
        remainingAllowedChecks = allowedChecks
    }

    func shouldContinue() -> Bool {
        guard remainingAllowedChecks > 0 else { return false }
        remainingAllowedChecks -= 1
        return true
    }
}

private final class FailOncePersistenceReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFailures = 1

    var isAllowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard remainingFailures > 0 else { return true }
        remainingFailures -= 1
        return false
    }
}

private final class CloudPersistenceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = true

    var isAllowed: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
