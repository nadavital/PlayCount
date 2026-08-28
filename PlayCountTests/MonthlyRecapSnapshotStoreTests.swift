import XCTest
@testable import PlayCount

final class MonthlyRecapSnapshotStoreTests: XCTestCase {
    func testRestoredDefaultsDoNotReuseDeviceIdentityOnDifferentHardware() {
        let priorID = "old-phone-device-id"
        XCTAssertNotEqual(
            MonthlyRecapSnapshotStore.resolvedDeviceIdentifier(
                keychainIdentifier: nil,
                defaultsIdentifier: priorID,
                storedVendorIdentifier: "old-vendor-id",
                currentVendorIdentifier: "new-vendor-id"
            ),
            priorID
        )
        XCTAssertEqual(
            MonthlyRecapSnapshotStore.resolvedDeviceIdentifier(
                keychainIdentifier: nil,
                defaultsIdentifier: priorID,
                storedVendorIdentifier: "same-vendor-id",
                currentVendorIdentifier: "same-vendor-id"
            ),
            priorID
        )
        XCTAssertEqual(
            MonthlyRecapSnapshotStore.resolvedDeviceIdentifier(
                keychainIdentifier: "keychain-id",
                defaultsIdentifier: priorID,
                storedVendorIdentifier: "old-vendor-id",
                currentVendorIdentifier: "new-vendor-id"
            ),
            "keychain-id"
        )
        XCTAssertNotEqual(
            MonthlyRecapSnapshotStore.resolvedDeviceIdentifier(
                keychainIdentifier: nil,
                defaultsIdentifier: priorID,
                storedVendorIdentifier: nil,
                currentVendorIdentifier: "new-vendor-id"
            ),
            priorID,
            "A legacy backup has no vendor marker, so its defaults UUID cannot safely identify the current hardware"
        )
        XCTAssertNil(
            MonthlyRecapSnapshotStore.resolvedLegacyBridgeIdentifier(
                existingBridgeIdentifier: "pending-old-phone-bridge",
                keychainIdentifier: nil,
                defaultsIdentifier: priorID,
                storedVendorIdentifier: "old-vendor-id",
                currentVendorIdentifier: "new-vendor-id",
                resolvedDeviceIdentifier: "new-phone-id"
            ),
            "A definite hardware mismatch must discard any bridge marker restored from the old phone"
        )
    }

    func testLegacyUpgradeBridgesFirstSnapshotIntoNewHardwareSafeStream() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLegacyDeviceBridge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 8, day: 1)
        let beforeUpgrade = date(year: 2026, month: 8, day: 3)
        let afterUpgrade = date(year: 2026, month: 8, day: 5)
        let later = date(year: 2026, month: 8, day: 7)
        do {
            let legacy = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "legacy-defaults-id"
            )
            _ = legacy.record(songs: [song(id: 1, title: "Continuous", playCount: 10)], at: baseline, reason: .foreground)
            _ = legacy.record(songs: [song(id: 1, title: "Continuous", playCount: 14)], at: beforeUpgrade, reason: .foreground)
        }

        do {
            let upgraded = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "new-keychain-id",
                legacyDeviceIdentifierToBridge: "legacy-defaults-id"
            )
            XCTAssertEqual(
                upgraded.record(
                    songs: [song(id: 1, title: "Continuous", playCount: 18)],
                    at: afterUpgrade,
                    reason: .foreground
                ).totalPlayDelta,
                8
            )
        }

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "new-keychain-id",
            legacyDeviceIdentifierToBridge: nil
        )
        XCTAssertEqual(
            relaunched.record(
                songs: [song(id: 1, title: "Continuous", playCount: 20)],
                at: later,
                reason: .foreground
            ).totalPlayDelta,
            10
        )
    }

    func testLegacyUpgradeCoverageRebaseRetiresBridgeMarkerAfterPersistence() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLegacyBridgeRebase-\(UUID().uuidString)", isDirectory: true)
        defer {
            MonthlyRecapSnapshotStore.debugSetLegacyDeviceIdentifierToBridge(nil)
            try? FileManager.default.removeItem(at: directory)
        }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 8, day: 1, hour: 8)
        let firstReduced = date(year: 2026, month: 8, day: 2, hour: 8)
        let confirmedReduced = date(year: 2026, month: 8, day: 2, hour: 9)
        let full = (1...20).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }
        let reduced = Array(full.prefix(10))
        do {
            let legacy = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "legacy-rebase-id"
            )
            _ = legacy.record(songs: full, at: baseline, reason: .appLaunch)
        }

        MonthlyRecapSnapshotStore.debugSetLegacyDeviceIdentifierToBridge("legacy-rebase-id")
        let upgraded = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "new-rebase-id",
            legacyDeviceIdentifierToBridge: "legacy-rebase-id"
        )
        _ = upgraded.record(songs: reduced, at: firstReduced, reason: .libraryChanged)
        XCTAssertEqual(
            MonthlyRecapSnapshotStore.debugLegacyDeviceIdentifierToBridge,
            "legacy-rebase-id"
        )
        _ = upgraded.record(songs: reduced, at: confirmedReduced, reason: .foreground)
        XCTAssertNil(MonthlyRecapSnapshotStore.debugLegacyDeviceIdentifierToBridge)

        let restored = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "restored-hardware-id",
            legacyDeviceIdentifierToBridge: MonthlyRecapSnapshotStore.debugLegacyDeviceIdentifierToBridge
        )
        _ = restored.record(
            songs: reduced,
            at: date(year: 2026, month: 8, day: 3, hour: 8),
            reason: .foreground
        )
        XCTAssertNil(MonthlyRecapSnapshotStore.debugLegacyDeviceIdentifierToBridge)
    }

    func testTransientLedgerLoadFailureRetriesBeforeCapturingNewCounters() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLoadRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let prior = date(year: 2026, month: 5, day: 3)
        let latest = date(year: 2026, month: 5, day: 5)
        do {
            let initial = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "load-retry"
            )
            _ = initial.record(songs: [song(id: 1, title: "Retried", playCount: 10)], at: baseline, reason: .foreground)
            _ = initial.record(songs: [song(id: 1, title: "Retried", playCount: 14)], at: prior, reason: .foreground)
        }

        let gate = PersistenceWriteGate()
        gate.isAllowed = false
        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "load-retry",
            persistenceReadAllowed: { gate.isAllowed }
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: prior).totalPlayDelta, 4)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)

        gate.isAllowed = true
        XCTAssertEqual(
            recovered.record(
                songs: [song(id: 1, title: "Retried", playCount: 18)],
                at: latest,
                reason: .foreground
            ).totalPlayDelta,
            8
        )
        XCTAssertTrue(recovered.isPersistenceHealthyForSync)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "load-retry"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: latest).totalPlayDelta, 8)
    }

    func testTransientMigrationSaveFailureRetainsFullLedgerAndRetriesWithoutRelaunch() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountMigrationSaveRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let prior = date(year: 2026, month: 5, day: 3)
        let latest = date(year: 2026, month: 5, day: 5)
        do {
            let legacy = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "migration-save-retry"
            )
            _ = legacy.record(songs: [song(id: 1, title: "Migrated", playCount: 10)], at: baseline, reason: .foreground)
            _ = legacy.record(songs: [song(id: 1, title: "Migrated", playCount: 14)], at: prior, reason: .foreground)
            legacy.debugInstallPreCounterReliabilityPolicyRecap(legacy.recap(forMonthContaining: prior))
        }

        let gate = PersistenceWriteGate()
        gate.isAllowed = false
        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "migration-save-retry",
            persistenceWriteAllowed: { gate.isAllowed }
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: prior).totalPlayDelta, 4)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)

        gate.isAllowed = true
        XCTAssertEqual(
            recovered.record(
                songs: [song(id: 1, title: "Migrated", playCount: 18)],
                at: latest,
                reason: .foreground
            ).totalPlayDelta,
            8
        )
        XCTAssertTrue(recovered.isPersistenceHealthyForSync)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "migration-save-retry"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: latest).totalPlayDelta, 8)
        XCTAssertEqual(relaunched.debugYearlyReliabilityPolicyVersion(for: 2026), 3)
    }

    func testIncompleteSQLiteMigrationRetriesSurvivingLegacyArchiveOnRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountIncompleteSQLiteMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 3)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-migration"
        )
        _ = source.record(songs: [song(id: 1, title: "Preserved", playCount: 10)], at: baseline, reason: .foreground)
        _ = source.record(songs: [song(id: 1, title: "Preserved", playCount: 14)], at: latest, reason: .foreground)
        try source.debugCreateLegacyArchiveForMigration()

        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        try Data("incomplete sqlite conversion".utf8).write(to: ledgerURL, options: .atomic)

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-migration"
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: latest).totalPlayDelta, 4)
        XCTAssertTrue(recovered.isPersistenceHealthyForSync)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("monthly-recap-snapshots.json").path
            )
        )

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-migration"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: latest).totalPlayDelta, 4)
    }

    func testTransientLegacyArchiveReadFailureRetriesWithoutCreatingEmptyLedger() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLegacyReadRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let prior = date(year: 2026, month: 5, day: 3)
        let latest = date(year: 2026, month: 5, day: 5)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-read-retry"
        )
        _ = source.record(songs: [song(id: 1, title: "Readable", playCount: 10)], at: baseline, reason: .foreground)
        _ = source.record(songs: [song(id: 1, title: "Readable", playCount: 14)], at: prior, reason: .foreground)
        try source.debugCreateLegacyArchiveForMigration()

        let readGate = PersistenceWriteGate()
        readGate.isAllowed = false
        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-read-retry",
            legacyArchiveReadAllowed: { readGate.isAllowed }
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: prior).totalPlayDelta, 4)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("recap-ledger.sqlite").path
            )
        )

        readGate.isAllowed = true
        XCTAssertEqual(
            recovered.record(
                songs: [song(id: 1, title: "Readable", playCount: 18)],
                at: latest,
                reason: .foreground
            ).totalPlayDelta,
            8
        )
        XCTAssertTrue(recovered.isPersistenceHealthyForSync)
        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-read-retry"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: latest).totalPlayDelta, 8)
    }

    func testLegacyMigrationPreservesTopLevelLedgersWhenSnapshotsAndCachesAreUnavailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLegacyLedgerOnlyMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2024, month: 1, day: 1)
        let latest = date(year: 2024, month: 1, day: 3)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-ledger-only"
        )
        _ = source.record(songs: [song(id: 1, title: "Archived", playCount: 10)], at: baseline, reason: .foreground)
        _ = source.record(songs: [song(id: 1, title: "Archived", playCount: 14)], at: latest, reason: .foreground)
        try source.debugCreateLegacyArchiveForMigration()

        let archiveURL = directory.appendingPathComponent("monthly-recap-snapshots.json")
        let archiveData = try Data(contentsOf: archiveURL)
        var archiveObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: archiveData) as? [String: Any]
        )
        archiveObject["snapshots"] = []
        try JSONSerialization.data(withJSONObject: archiveObject, options: [.prettyPrinted, .sortedKeys])
            .write(to: archiveURL, options: .atomic)
        try Data("corrupt primary".utf8).write(
            to: directory.appendingPathComponent("recap-summaries.json"),
            options: .atomic
        )
        try Data("corrupt backup".utf8).write(
            to: directory.appendingPathComponent("recap-summaries.previous.json"),
            options: .atomic
        )

        let migrated = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-ledger-only"
        )
        XCTAssertEqual(migrated.recap(forMonthContaining: latest).totalPlayDelta, 4)
        XCTAssertEqual(migrated.syncedYearlyRecap(for: 2024)?.totalPlayDelta, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))
    }

    func testFailedLegacyArchiveRetirementCannotLaterRestoreStaleJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLegacyRetirementRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let prior = date(year: 2026, month: 5, day: 3)
        let latest = date(year: 2026, month: 5, day: 5)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-retirement"
        )
        _ = source.record(songs: [song(id: 1, title: "Retired", playCount: 10)], at: baseline, reason: .foreground)
        _ = source.record(songs: [song(id: 1, title: "Retired", playCount: 14)], at: prior, reason: .foreground)
        try source.debugCreateLegacyArchiveForMigration()

        let retirementGate = PersistenceWriteGate()
        retirementGate.isAllowed = false
        let migrating = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-retirement",
            legacyArchiveRetirementAllowed: { retirementGate.isAllowed }
        )
        XCTAssertEqual(migrating.recap(forMonthContaining: prior).totalPlayDelta, 4)
        XCTAssertFalse(migrating.isPersistenceHealthyForSync)
        let archiveURL = directory.appendingPathComponent("monthly-recap-snapshots.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        retirementGate.isAllowed = true
        XCTAssertEqual(
            migrating.record(
                songs: [song(id: 1, title: "Retired", playCount: 16)],
                at: latest,
                reason: .foreground
            ).totalPlayDelta,
            6
        )
        XCTAssertTrue(migrating.isPersistenceHealthyForSync)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveURL.path))

        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        try Data("later unreadable ledger".utf8).write(to: ledgerURL, options: .atomic)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-shm"))
        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "legacy-retirement"
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: latest).totalPlayDelta, 6)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
    }

    func testVerifiedLedgerMarkerPreventsStaleJSONResurrectionAfterRetirementFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLedgerAuthorityMarker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let prior = date(year: 2026, month: 5, day: 3)
        let latest = date(year: 2026, month: 5, day: 5)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "ledger-authority-marker"
        )
        _ = source.record(songs: [song(id: 1, title: "Saved", playCount: 10)], at: baseline, reason: .foreground)
        _ = source.record(songs: [song(id: 1, title: "Saved", playCount: 14)], at: prior, reason: .foreground)
        try source.debugCreateLegacyArchiveForMigration()

        let retirementGate = PersistenceWriteGate()
        retirementGate.isAllowed = false
        let migrated = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "ledger-authority-marker",
            legacyArchiveRetirementAllowed: { retirementGate.isAllowed }
        )
        XCTAssertEqual(
            migrated.record(
                songs: [song(id: 1, title: "Saved", playCount: 16)],
                at: latest,
                reason: .foreground
            ).totalPlayDelta,
            6
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("monthly-recap-snapshots.json").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("recap-ledger.authoritative").path
        ))

        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        try Data("broken ledger".utf8).write(to: ledgerURL, options: .atomic)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-shm"))
        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "ledger-authority-marker",
            legacyArchiveRetirementAllowed: { false }
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: latest).totalPlayDelta, 6)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
    }

    func testHealthySQLiteLedgerImmediatelyCreatesAuthorityMarker() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountImmediateAuthorityMarker-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "immediate-authority-marker"
        )
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 3)
        _ = source.record(songs: [song(id: 1, title: "Saved", playCount: 10)], at: baseline, reason: .foreground)
        _ = source.record(songs: [song(id: 1, title: "Saved", playCount: 14)], at: latest, reason: .foreground)

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("recap-ledger.authoritative").path
        ))
        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        for url in [ledgerURL, URL(fileURLWithPath: ledgerURL.path + "-wal"), URL(fileURLWithPath: ledgerURL.path + "-shm")] {
            try? FileManager.default.removeItem(at: url)
        }

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "immediate-authority-marker"
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: latest).totalPlayDelta, 4)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
    }

    func testMalformedPresentLegacyLedgerArrayFailsClosedWithoutRetiringArchive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountMalformedLegacyLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "malformed-legacy-ledger"
        )
        _ = source.record(
            songs: [song(id: 1, title: "Saved", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        try source.debugCreateLegacyArchiveForMigration()
        let archiveURL = directory.appendingPathComponent("monthly-recap-snapshots.json")
        var archiveObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as? [String: Any]
        )
        archiveObject["monthlyLedgers"] = NSNull()
        try JSONSerialization.data(withJSONObject: archiveObject, options: [.prettyPrinted, .sortedKeys])
            .write(to: archiveURL, options: .atomic)
        try Data("bad".utf8).write(
            to: directory.appendingPathComponent("recap-summaries.json"),
            options: .atomic
        )
        try Data("bad".utf8).write(
            to: directory.appendingPathComponent("recap-summaries.previous.json"),
            options: .atomic
        )

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "malformed-legacy-ledger"
        )
        recovered.prepareStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
    }

    func testFinalNonArrayLegacyLedgerValueFailsClosedWithoutRetiringArchive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountFinalMalformedLegacyLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "final-malformed-legacy-ledger"
        )
        _ = source.record(
            songs: [song(id: 1, title: "Saved", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        try source.debugCreateLegacyArchiveForMigration()
        let archiveURL = directory.appendingPathComponent("monthly-recap-snapshots.json")
        var archiveObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: archiveURL)) as? [String: Any]
        )
        archiveObject.removeValue(forKey: "syncedYearlyRecaps")
        var archiveData = try JSONSerialization.data(withJSONObject: archiveObject)
        XCTAssertEqual(archiveData.last, UInt8(ascii: "}"))
        archiveData.removeLast()
        archiveData.append(Data(",\"syncedYearlyRecaps\":{}}".utf8))
        try archiveData.write(to: archiveURL, options: .atomic)

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "final-malformed-legacy-ledger"
        )
        recovered.prepareStorage()
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
    }

    func testAuthorityMarkerBlocksStaleJSONWhenLedgerIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountMissingAuthoritativeLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "missing-authoritative-ledger"
        )
        _ = source.record(
            songs: [song(id: 1, title: "Stale", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        try source.debugCreateLegacyArchiveForMigration()
        try Data("v1".utf8).write(
            to: directory.appendingPathComponent("recap-ledger.authoritative"),
            options: .atomic
        )
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("recap-ledger.sqlite"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("recap-summaries.json"))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("recap-summaries.previous.json"))

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "missing-authoritative-ledger"
        )
        recovered.prepareStorage()
        XCTAssertTrue(recovered.cachedRecapSummaries().isEmpty)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("monthly-recap-snapshots.json").path
        ))
    }

    func testOldPolicyRemoteSnapshotsCannotReinflateCorrectedCurrentPolicyRecap() {
        let corrected = makeStore(named: "corrected-v3-target")
        let stale = makeStore(named: "stale-v2-source")
        let baseline = date(year: 2026, month: 8, day: 1)
        let latest = date(year: 2026, month: 8, day: 3)
        _ = corrected.record(songs: [song(id: 1, title: "Correct", playCount: 10)], at: baseline, reason: .foreground)
        _ = corrected.record(songs: [song(id: 1, title: "Correct", playCount: 15)], at: latest, reason: .foreground)
        _ = stale.record(songs: [song(id: 2, title: "Stale", playCount: 0)], at: baseline, reason: .foreground)
        _ = stale.record(songs: [song(id: 2, title: "Stale", playCount: 500)], at: latest, reason: .foreground)
        let stalePayloads = stale.syncPayloads().map {
            RecapSnapshotSyncPayload(
                id: $0.id,
                capturedAt: $0.capturedAt,
                counterSignature: $0.counterSignature,
                reliabilityPolicyVersion: 2,
                encodedSnapshot: $0.encodedSnapshot
            )
        }

        XCTAssertFalse(corrected.mergeSyncPayloads(stalePayloads, now: latest))
        XCTAssertEqual(corrected.recap(forMonthContaining: latest).totalPlayDelta, 5)
    }

    func testUnreadableLedgerFallsBackToSummaryWithoutOverwritingHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountUnreadableLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 3)
        do {
            let store = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "summary-fallback"
            )
            _ = store.record(songs: [song(id: 1, title: "Saved", playCount: 10)], at: baseline, reason: .foreground)
            _ = store.record(songs: [song(id: 1, title: "Saved", playCount: 14)], at: latest, reason: .foreground)
            XCTAssertEqual(store.recap(forMonthContaining: latest).totalPlayDelta, 4)
        }

        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        try Data("not a sqlite ledger".utf8).write(to: ledgerURL, options: .atomic)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-shm"))
        let corruptBytes = try Data(contentsOf: ledgerURL)

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-fallback"
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: latest).totalPlayDelta, 4)
        XCTAssertFalse(recovered.isPersistenceHealthyForSync)
        _ = recovered.record(
            songs: [song(id: 1, title: "Saved", playCount: 20)],
            at: date(year: 2026, month: 5, day: 4),
            reason: .foreground
        )
        XCTAssertEqual(try Data(contentsOf: ledgerURL), corruptBytes)
    }

    func testSummaryFallbackUsesCurrentMonthInsteadOfLargerStaleBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountSummaryPriority-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 3)
        let inflatedDate = date(year: 2026, month: 5, day: 4)
        do {
            let store = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "summary-priority"
            )
            _ = store.record(songs: [song(id: 1, title: "Saved", playCount: 10)], at: baseline, reason: .foreground)
            _ = store.record(songs: [song(id: 1, title: "Saved", playCount: 14)], at: latest, reason: .foreground)
            let goodSummary = try Data(contentsOf: directory.appendingPathComponent("recap-summaries.json"))
            _ = store.record(
                songs: [song(id: 1, title: "Saved", playCount: 30)],
                at: inflatedDate,
                reason: .foreground
            )
            let inflatedSummary = try Data(contentsOf: directory.appendingPathComponent("recap-summaries.json"))
            try goodSummary.write(to: directory.appendingPathComponent("recap-summaries.json"), options: .atomic)
            try inflatedSummary.write(
                to: directory.appendingPathComponent("recap-summaries.previous.json"),
                options: .atomic
            )
        }
        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        try Data("broken".utf8).write(to: ledgerURL, options: .atomic)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: ledgerURL.path + "-shm"))

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-priority"
        )
        XCTAssertEqual(recovered.recap(forMonthContaining: latest).totalPlayDelta, 4)
    }

    func testCachedPresentationUsesBackupAndCorruptPrimaryCannotReplaceIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountSummaryBackupValidation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 3)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-backup-validation"
        )
        _ = store.record(songs: [song(id: 1, title: "Saved", playCount: 10)], at: baseline, reason: .foreground)
        _ = store.record(songs: [song(id: 1, title: "Saved", playCount: 14)], at: latest, reason: .foreground)

        let primaryURL = directory.appendingPathComponent("recap-summaries.json")
        let backupURL = directory.appendingPathComponent("recap-summaries.previous.json")
        let lastGoodBackup = try Data(contentsOf: primaryURL)
        try lastGoodBackup.write(to: backupURL, options: .atomic)
        try Data("corrupt primary".utf8).write(to: primaryURL, options: .atomic)

        _ = store.record(
            songs: [song(id: 1, title: "Saved", playCount: 16)],
            at: date(year: 2026, month: 5, day: 4),
            reason: .foreground
        )
        XCTAssertEqual(try Data(contentsOf: backupURL), lastGoodBackup)

        try Data("corrupt again".utf8).write(to: primaryURL, options: .atomic)
        let coldStore = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-backup-validation"
        )
        XCTAssertEqual(coldStore.cachedRecapSummaries().last?.totalPlayDelta, 4)
    }

    func testPrepareStorageRegeneratesCorruptSummaryCacheFromHealthyLedger() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountSummaryRegeneration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 3)
        do {
            let source = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "summary-regeneration"
            )
            _ = source.record(songs: [song(id: 1, title: "Saved", playCount: 10)], at: baseline, reason: .foreground)
            _ = source.record(songs: [song(id: 1, title: "Saved", playCount: 14)], at: latest, reason: .foreground)
        }
        try Data("corrupt primary".utf8).write(
            to: directory.appendingPathComponent("recap-summaries.json"),
            options: .atomic
        )
        try Data("corrupt backup".utf8).write(
            to: directory.appendingPathComponent("recap-summaries.previous.json"),
            options: .atomic
        )

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-regeneration"
        )
        XCTAssertTrue(recovered.cachedRecapSummaries().isEmpty)
        recovered.prepareStorage()
        XCTAssertEqual(recovered.cachedRecapSummaries().last?.totalPlayDelta, 4)
    }

    func testPrepareStorageRegeneratesValidButStaleSummaryCacheFromHealthyLedger() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountStaleSummaryRegeneration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let primaryURL = directory.appendingPathComponent("recap-summaries.json")
        do {
            let source = MonthlyRecapSnapshotStore(
                directoryURL: directory,
                calendar: calendar,
                deviceIdentifier: "stale-summary-regeneration"
            )
            _ = source.record(
                songs: [song(id: 1, title: "Saved", playCount: 10)],
                at: date(year: 2026, month: 5, day: 1),
                reason: .foreground
            )
            _ = source.record(
                songs: [song(id: 1, title: "Saved", playCount: 14)],
                at: date(year: 2026, month: 5, day: 3),
                reason: .foreground
            )
            let staleButValid = try Data(contentsOf: primaryURL)
            _ = source.record(
                songs: [song(id: 1, title: "Saved", playCount: 20)],
                at: date(year: 2026, month: 5, day: 4),
                reason: .foreground
            )
            try staleButValid.write(to: primaryURL, options: .atomic)
        }

        let recovered = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "stale-summary-regeneration"
        )
        XCTAssertEqual(recovered.cachedRecapSummaries().last?.totalPlayDelta, 4)
        recovered.prepareStorage()
        XCTAssertEqual(recovered.cachedRecapSummaries().last?.totalPlayDelta, 10)
    }

    func testTransientSaveFailureKeepsPendingSnapshotsAndRetriesWithoutRelaunch() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountSaveRetry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = PersistenceWriteGate()
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "save-retry",
            persistenceWriteAllowed: { gate.isAllowed }
        )
        _ = store.record(
            songs: [song(id: 1, title: "Pending", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Pending", playCount: 14)],
            at: date(year: 2026, month: 5, day: 3),
            reason: .foreground
        )

        gate.isAllowed = false
        let pending = store.record(
            songs: [song(id: 1, title: "Pending", playCount: 16)],
            at: date(year: 2026, month: 5, day: 4),
            reason: .foreground
        )
        XCTAssertEqual(pending.totalPlayDelta, 6)
        XCTAssertFalse(store.isPersistenceHealthyForSync)

        gate.isAllowed = true
        let retried = store.record(
            songs: [song(id: 1, title: "Pending", playCount: 18)],
            at: date(year: 2026, month: 5, day: 5),
            reason: .foreground
        )
        XCTAssertEqual(retried.totalPlayDelta, 8)
        XCTAssertTrue(store.isPersistenceHealthyForSync)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "save-retry"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: date(year: 2026, month: 5, day: 5)).totalPlayDelta, 8)
    }

    func testRecordDoesNotPersistWhenCommitGateIsClosed() {
        let store = makeStore(named: "record-gated")
        _ = store.record(
            songs: [song(id: 1, title: "Private", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground,
            shouldCommit: { false }
        )

        XCTAssertTrue(store.syncPayloads().isEmpty)
    }

    func testMergeDoesNotPersistWhenCommitGateClosesInsideTransaction() {
        let source = makeStore(named: "merge-gated-source")
        let target = makeStore(named: "merge-gated-target")
        _ = source.record(
            songs: [song(id: 1, title: "Remote", playCount: 10)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        let gate = SnapshotCommitGate(allowedChecks: 1)

        XCTAssertFalse(target.mergeSyncPayloads(source.syncPayloads()) {
            gate.shouldCommit()
        })
        XCTAssertTrue(target.syncPayloads().isEmpty)
    }

    func testRecapPayloadRoundTripMergesIntoFreshStore() {
        let sourceStore = makeStore(named: "source")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let latestDate = date(year: 2026, month: 5, day: 5, hour: 12)

        _ = sourceStore.record(
            songs: [song(id: 1, title: "First", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        let sourceRecap = sourceStore.record(
            songs: [song(id: 1, title: "First", playCount: 14)],
            at: latestDate,
            reason: .foreground
        )

        XCTAssertEqual(sourceRecap.totalPlayDelta, 4)
        XCTAssertEqual(sourceRecap.topSongs.first?.title, "First")

        let payloads = sourceStore.syncPayloads()
        XCTAssertEqual(payloads.count, 2)

        let targetStore = makeStore(named: "target")
        XCTAssertTrue(targetStore.mergeSyncPayloads(payloads, now: latestDate))

        let targetRecap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(targetRecap.totalPlayDelta, sourceRecap.totalPlayDelta)
        XCTAssertEqual(targetRecap.topSongs.first?.playDelta, 4)
    }

    func testArchivedRecapSurvivesWhenNewestCloudSnapshotRecordIsMissing() throws {
        let sourceStore = makeStore(named: "redundant-summary-source")
        let baseline = date(year: 2026, month: 5, day: 1)
        let latest = date(year: 2026, month: 5, day: 5)
        _ = sourceStore.record(
            songs: [song(id: 1, title: "Durable", playCount: 10)],
            at: baseline,
            reason: .foreground
        )
        _ = sourceStore.record(
            songs: [song(id: 1, title: "Durable", playCount: 18)],
            at: latest,
            reason: .foreground
        )

        let payloads = sourceStore.syncPayloads().sorted { $0.capturedAt < $1.capturedAt }
        XCTAssertGreaterThan(payloads.count, 1)
        XCTAssertEqual(payloads.filter { $0.encodedRecaps != nil }.count, 2)

        let restored = makeStore(named: "redundant-summary-target")
        XCTAssertTrue(restored.mergeSyncPayloads(Array(payloads.dropLast()), now: latest))
        XCTAssertEqual(restored.recap(forMonthContaining: latest).totalPlayDelta, 8)
    }

    func testSyncedRecapSummaryKeepsRankedListsConsistentAcrossDevices() {
        let phoneStore = makeStore(named: "summary-phone")
        let iPadStore = makeStore(named: "summary-ipad")
        let baselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)

        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 10),
                song(id: 2, title: "Phone Runner Up", playCount: 20)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 17),
                song(id: 2, title: "Phone Runner Up", playCount: 25)
            ],
            at: latestDate,
            reason: .foreground
        )

        _ = iPadStore.record(
            songs: [song(id: 3, title: "iPad Local", playCount: 30)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 3, title: "iPad Local", playCount: 42)],
            at: latestDate,
            reason: .foreground
        )

        let phonePayloads = phoneStore.localSyncPayloads()
        XCTAssertFalse(phonePayloads.isEmpty)
        XCTAssertEqual(phonePayloads.filter { $0.encodedRecaps != nil }.count, min(2, phonePayloads.count))
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phonePayloads, now: latestDate))

        let recap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 12)
        XCTAssertEqual(recap.playedSongCount, 2)
        XCTAssertEqual(recap.topSongs.map(\.title), ["Phone Favorite", "Phone Runner Up"])
    }

    func testPreviousMonthsSyncAsArchivedRecapsWithoutFullSnapshotHistory() {
        let sourceStore = makeStore(named: "archive-source")
        let targetStore = makeStore(named: "archive-target")
        let aprilBaseline = date(year: 2026, month: 4, day: 1, hour: 8)
        let aprilLatest = date(year: 2026, month: 4, day: 20, hour: 8)
        let mayBaseline = date(year: 2026, month: 5, day: 1, hour: 8)
        let mayLatest = date(year: 2026, month: 5, day: 8, hour: 8)

        _ = sourceStore.record(
            songs: [song(id: 1, title: "Archive Song", playCount: 10)],
            at: aprilBaseline,
            reason: .manualRefresh
        )
        _ = sourceStore.record(
            songs: [song(id: 1, title: "Archive Song", playCount: 14)],
            at: aprilLatest,
            reason: .foreground
        )
        _ = sourceStore.record(
            songs: [song(id: 1, title: "Archive Song", playCount: 14)],
            at: mayBaseline,
            reason: .manualRefresh
        )
        _ = sourceStore.record(
            songs: [song(id: 1, title: "Archive Song", playCount: 17)],
            at: mayLatest,
            reason: .foreground
        )

        let payloads = sourceStore.localSyncPayloads()

        // The active month needs its prior-month baseline plus its first and
        // latest observations; archived months travel as the compact summary.
        XCTAssertEqual(payloads.count, 3)
        XCTAssertEqual(payloads.filter { $0.encodedRecaps != nil }.count, 2)
        XCTAssertTrue(targetStore.mergeSyncPayloads(payloads, now: mayLatest))
        XCTAssertEqual(targetStore.recap(forMonthContaining: aprilLatest).totalPlayDelta, 4)
        XCTAssertEqual(targetStore.recap(forMonthContaining: mayLatest).totalPlayDelta, 3)
    }

    func testSyncedRecapSummaryWinsWhenLocalDeviceHasDifferentEqualQualityRankings() {
        let phoneStore = makeStore(named: "equal-summary-phone")
        let iPadStore = makeStore(named: "equal-summary-ipad")
        let baselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let phoneLatestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let iPadLatestDate = date(year: 2026, month: 5, day: 8, hour: 9)

        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 10),
                song(id: 2, title: "Phone Runner Up", playCount: 20)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 17),
                song(id: 2, title: "Phone Runner Up", playCount: 25)
            ],
            at: phoneLatestDate,
            reason: .foreground
        )

        _ = iPadStore.record(
            songs: [
                song(id: 3, title: "iPad Favorite", playCount: 30),
                song(id: 4, title: "iPad Runner Up", playCount: 40)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [
                song(id: 3, title: "iPad Favorite", playCount: 37),
                song(id: 4, title: "iPad Runner Up", playCount: 45)
            ],
            at: iPadLatestDate,
            reason: .foreground
        )

        XCTAssertEqual(iPadStore.recap(forMonthContaining: iPadLatestDate).topSongs.first?.title, "iPad Favorite")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phoneStore.localSyncPayloads(), now: iPadLatestDate))

        let recap = iPadStore.recap(forMonthContaining: iPadLatestDate)
        XCTAssertEqual(recap.totalPlayDelta, 12)
        XCTAssertEqual(recap.playedSongCount, 2)
        XCTAssertEqual(recap.topSongs.map(\.title), ["Phone Favorite", "Phone Runner Up"])
    }

    func testSyncedPhoneRecapWinsOverLaterEmptyLocalDeviceSnapshot() {
        let phoneStore = makeStore(named: "phone")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let phoneLatestDate = date(year: 2026, month: 5, day: 5, hour: 12)
        let iPadLaterDate = date(year: 2026, month: 5, day: 5, hour: 13)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 14)],
            at: phoneLatestDate,
            reason: .foreground
        )

        let iPadStore = makeStore(named: "ipad")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phoneStore.syncPayloads(), now: iPadLaterDate))
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Local Empty Baseline", playCount: 0)],
            at: iPadLaterDate,
            reason: .foreground
        )

        let recap = iPadStore.recap(forMonthContaining: iPadLaterDate)
        XCTAssertEqual(recap.totalPlayDelta, 4)
        XCTAssertEqual(recap.topSongs.first?.title, "Phone Song")
    }

    func testEstablishedPhoneStreamWinsOverLaterInflatedDeviceStream() {
        let phoneStore = makeStore(named: "phone-established")
        let iPadStore = makeStore(named: "ipad-inflated")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let phoneLatestDate = date(year: 2026, month: 5, day: 5, hour: 12)
        let iPadBaselineDate = date(year: 2026, month: 5, day: 6, hour: 10)
        let iPadLatestDate = date(year: 2026, month: 5, day: 6, hour: 11)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 14)],
            at: phoneLatestDate,
            reason: .foreground
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Inflated iPad Song", playCount: 1)],
            at: iPadBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Inflated iPad Song", playCount: 10_000)],
            at: iPadLatestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-established")
        XCTAssertTrue(targetStore.mergeSyncPayloads(phoneStore.syncPayloads() + iPadStore.syncPayloads(), now: iPadLatestDate))

        let recap = targetStore.recap(forMonthContaining: iPadLatestDate)
        XCTAssertEqual(recap.totalPlayDelta, 4)
        XCTAssertEqual(recap.topSongs.first?.title, "Phone Song")
    }

    func testPartialBaselineDoesNotInflateLaterFullLibrarySnapshot() {
        let store = makeStore(named: "partial-baseline")
        let partialDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let fullDate = date(year: 2026, month: 5, day: 1, hour: 10)
        let fullSongs = (1...1_000).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }

        _ = store.record(
            songs: [song(id: 1, title: "Song 1", playCount: 1)],
            at: partialDate,
            reason: .appLaunch
        )
        _ = store.record(
            songs: fullSongs,
            at: fullDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: fullDate)
        XCTAssertEqual(recap.totalPlayDelta, 0)
        XCTAssertTrue(recap.topSongs.isEmpty)
    }

    func testModestPartialBaselineDoesNotInflateWhenFullLibraryAppears() {
        let store = makeStore(named: "modest-partial-baseline")
        let partialDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let fullDate = date(year: 2026, month: 5, day: 1, hour: 9)
        let confirmedDate = date(year: 2026, month: 5, day: 1, hour: 10)
        let playedDate = date(year: 2026, month: 5, day: 1, hour: 11)
        let partial = (1...5).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 0)
        }
        let full = (1...10).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: $0 <= 5 ? 0 : 1)
        }

        _ = store.record(songs: partial, at: partialDate, reason: .appLaunch)
        let recap = store.record(songs: full, at: fullDate, reason: .foreground)

        XCTAssertEqual(recap.totalPlayDelta, 0)
        XCTAssertTrue(recap.topSongs.isEmpty)
        XCTAssertTrue(store.reliabilityStatus().isUsingLastReliableUpdate)

        let confirmed = store.record(songs: full, at: confirmedDate, reason: .foreground)
        XCTAssertEqual(confirmed.totalPlayDelta, 0)
        XCTAssertFalse(store.reliabilityStatus().isUsingLastReliableUpdate)

        let played = (1...10).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: $0 <= 5 ? 1 : 2)
        }
        let updated = store.record(songs: played, at: playedDate, reason: .playbackChanged)
        XCTAssertEqual(updated.totalPlayDelta, 10)
    }

    func testNinetyPercentPartialObservationCannotInflateWhenMissingSongReturns() {
        let store = makeStore(named: "ninety-percent-partial")
        let baselineDate = date(year: 2026, month: 8, day: 1, hour: 8)
        let partialDate = date(year: 2026, month: 8, day: 10, hour: 8)
        let recoveredDate = date(year: 2026, month: 8, day: 20, hour: 8)
        let fullLibrary = (1...10).map { id in
            song(
                id: UInt64(id),
                title: "Song \(id)",
                playCount: id == 10 ? 1_000 : 0
            )
        }
        let partialLibrary = Array(fullLibrary.prefix(9))

        _ = store.record(songs: fullLibrary, at: baselineDate, reason: .appLaunch)
        let held = store.record(songs: partialLibrary, at: partialDate, reason: .foreground)
        XCTAssertEqual(held.totalPlayDelta, 0)
        XCTAssertTrue(store.reliabilityStatus().isUsingLastReliableUpdate)

        let recovered = store.record(songs: fullLibrary, at: recoveredDate, reason: .foreground)
        XCTAssertEqual(recovered.totalPlayDelta, 0)
        XCTAssertTrue(recovered.topSongs.isEmpty)
        XCTAssertFalse(store.reliabilityStatus().isUsingLastReliableUpdate)
    }

    func testConfirmedLargeLibraryDeletionRebasesWithoutFreezingFuturePlays() {
        let store = makeStore(named: "confirmed-library-deletion")
        let baselineDate = date(year: 2026, month: 8, day: 1, hour: 8)
        let deletionDate = date(year: 2026, month: 8, day: 2, hour: 8)
        let confirmationDate = date(year: 2026, month: 8, day: 2, hour: 9)
        let listeningDate = date(year: 2026, month: 8, day: 2, hour: 10)
        let full = (1...20).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }
        let reduced = (1...10).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }
        let played = (1...10).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 101)
        }

        _ = store.record(songs: full, at: baselineDate, reason: .appLaunch)
        let held = store.record(songs: reduced, at: deletionDate, reason: .libraryChanged)
        XCTAssertEqual(held.totalPlayDelta, 0)
        XCTAssertTrue(store.reliabilityStatus().isUsingLastReliableUpdate)

        let rebased = store.record(songs: reduced, at: confirmationDate, reason: .foreground)
        XCTAssertEqual(rebased.totalPlayDelta, 0)
        XCTAssertFalse(store.reliabilityStatus().isUsingLastReliableUpdate)

        let updated = store.record(songs: played, at: listeningDate, reason: .playbackChanged)
        XCTAssertEqual(updated.totalPlayDelta, 10)
        XCTAssertEqual(updated.topSongs.count, 10)
    }

    func testDifferentPartialMembershipDoesNotConfirmCoverageRebase() {
        let store = makeStore(named: "rotating-partial-coverage")
        let baselineDate = date(year: 2026, month: 8, day: 1, hour: 8)
        let firstPartialDate = date(year: 2026, month: 8, day: 2, hour: 8)
        let differentPartialDate = date(year: 2026, month: 8, day: 2, hour: 9)
        let confirmedDate = date(year: 2026, month: 8, day: 2, hour: 10)
        let full = (1...10).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }
        let firstHalf = Array(full.prefix(5))
        let secondHalf = Array(full.suffix(5))

        _ = store.record(songs: full, at: baselineDate, reason: .appLaunch)
        _ = store.record(songs: firstHalf, at: firstPartialDate, reason: .foreground)
        let stillHeld = store.record(songs: secondHalf, at: differentPartialDate, reason: .foreground)
        XCTAssertEqual(stillHeld.totalPlayDelta, 0)
        XCTAssertTrue(store.reliabilityStatus().isUsingLastReliableUpdate)

        let rebased = store.record(songs: secondHalf, at: confirmedDate, reason: .foreground)
        XCTAssertEqual(rebased.totalPlayDelta, 0)
        XCTAssertFalse(store.reliabilityStatus().isUsingLastReliableUpdate)
    }

    func testTransientOfflineCounterRegressionDoesNotInflateRecapAfterRecovery() {
        let store = makeStore(named: "offline-counter-regression")
        let baselineDate = date(year: 2026, month: 7, day: 31, hour: 22)
        let firstAugustCapture = date(year: 2026, month: 8, day: 4, hour: 10)
        let offlineCapture = date(year: 2026, month: 8, day: 4, hour: 11)
        let recoveredCapture = date(year: 2026, month: 8, day: 4, hour: 12)

        func songs(playCount: Int) -> [TopSong] {
            (1...30).map {
                song(id: UInt64($0), title: "Song \($0)", playCount: playCount)
            }
        }

        _ = store.record(songs: songs(playCount: 100), at: baselineDate, reason: .foreground)
        let beforeOffline = store.record(
            songs: songs(playCount: 101),
            at: firstAugustCapture,
            reason: .foreground
        )
        let whileOffline = store.record(
            songs: songs(playCount: 0),
            at: offlineCapture,
            reason: .foreground
        )
        let afterRecovery = store.record(
            songs: songs(playCount: 102),
            at: recoveredCapture,
            reason: .foreground
        )

        XCTAssertEqual(beforeOffline.totalPlayDelta, 30)
        XCTAssertEqual(whileOffline.totalPlayDelta, 30)
        XCTAssertEqual(whileOffline.generatedAt, firstAugustCapture)
        XCTAssertEqual(afterRecovery.totalPlayDelta, 60)
        XCTAssertEqual(afterRecovery.topSongs.count, 30)
        XCTAssertTrue(afterRecovery.topSongs.allSatisfy { $0.playDelta == 2 })
    }

    func testEmptyOfflineQueryDoesNotReplaceTrustedSnapshotAcrossRelaunch() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountEmptyOfflineQuery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "empty-offline-query"
        )
        let baselineDate = date(year: 2026, month: 7, day: 31, hour: 22)
        let firstCapture = date(year: 2026, month: 8, day: 4, hour: 10)
        let offlineCapture = date(year: 2026, month: 8, day: 4, hour: 11)
        let recoveredCapture = date(year: 2026, month: 8, day: 4, hour: 12)

        func songs(playCount: Int) -> [TopSong] {
            (1...30).map {
                song(id: UInt64($0), title: "Song \($0)", playCount: playCount)
            }
        }

        _ = store.record(songs: songs(playCount: 100), at: baselineDate, reason: .foreground)
        _ = store.record(songs: songs(playCount: 101), at: firstCapture, reason: .foreground)
        let held = store.record(songs: [], at: offlineCapture, reason: .foreground)
        XCTAssertEqual(held.totalPlayDelta, 30)
        XCTAssertEqual(held.generatedAt, firstCapture)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "empty-offline-query"
        )
        let recovered = relaunched.record(
            songs: songs(playCount: 102),
            at: recoveredCapture,
            reason: .foreground
        )

        XCTAssertEqual(recovered.totalPlayDelta, 60)
        XCTAssertFalse(relaunched.reliabilityStatus().isUsingLastReliableUpdate)
    }

    func testSmallLibraryCounterCollapseIsQuarantinedAndReportedWithoutMediaNames() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountSmallLibraryRegression-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "small-library-counter-regression"
        )
        let baselineDate = date(year: 2026, month: 7, day: 31, hour: 22)
        let firstCapture = date(year: 2026, month: 8, day: 4, hour: 10)
        let offlineCapture = date(year: 2026, month: 8, day: 4, hour: 11)
        let recoveredCapture = date(year: 2026, month: 8, day: 4, hour: 12)

        _ = store.record(
            songs: [song(id: 1, title: "Private Song Name", artist: "Private Artist", playCount: 50)],
            at: baselineDate,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Private Song Name", artist: "Private Artist", playCount: 51)],
            at: firstCapture,
            reason: .foreground
        )
        let whileOffline = store.record(
            songs: [song(id: 1, title: "Private Song Name", artist: "Private Artist", playCount: 0)],
            at: offlineCapture,
            reason: .foreground
        )

        XCTAssertEqual(whileOffline.totalPlayDelta, 1)
        XCTAssertTrue(store.reliabilityStatus().isUsingLastReliableUpdate)
        XCTAssertEqual(store.reliabilityStatus().recentRejectedObservationCount, 1)
        let diagnostics = store.privacySafeDiagnostics(at: offlineCapture)
        XCTAssertFalse(diagnostics.contains("Private Song Name"))
        XCTAssertFalse(diagnostics.contains("Private Artist"))
        XCTAssertTrue(diagnostics.contains("Recent rejected observations: 1"))

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "small-library-counter-regression"
        )
        XCTAssertTrue(relaunched.reliabilityStatus().isUsingLastReliableUpdate)

        let recovered = relaunched.record(
            songs: [song(id: 1, title: "Private Song Name", artist: "Private Artist", playCount: 52)],
            at: recoveredCapture,
            reason: .foreground
        )
        XCTAssertEqual(recovered.totalPlayDelta, 2)
        XCTAssertFalse(relaunched.reliabilityStatus().isUsingLastReliableUpdate)
    }

    func testDiagnosticsReportExplainsMonthlyCoverageWithoutMediaNames() throws {
        let store = makeStore(named: "diagnostics-coverage")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 22)
        let mayDate = date(year: 2026, month: 5, day: 20, hour: 12)
        let juneStart = date(year: 2026, month: 6, day: 1, hour: 8)
        let juneDate = date(year: 2026, month: 6, day: 18, hour: 12)

        _ = store.record(
            songs: [song(id: 1, title: "Private May Song", artist: "Private Artist", playCount: 100)],
            at: baselineDate,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Private May Song", artist: "Private Artist", playCount: 104)],
            at: mayDate,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Private May Song", artist: "Private Artist", playCount: 104)],
            at: juneStart,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Private May Song", artist: "Private Artist", playCount: 107)],
            at: juneDate,
            reason: .foreground
        )

        let report = store.recapDiagnosticsReport(at: juneDate)
        let yearly = try XCTUnwrap(store.syncedYearlyRecap(for: 2026))

        XCTAssertTrue(report.hasCanonicalMonthLedger)
        XCTAssertTrue(report.yearlyTotalsMatchMonthlyLedgers)
        XCTAssertEqual(report.months.reduce(0) { $0 + $1.totalPlayDelta }, yearly.totalPlayDelta)
        XCTAssertEqual(report.months.first { Calendar.current.component(.month, from: $0.monthStart) == 6 }?.totalPlayDelta, 3)
        XCTAssertTrue(report.months.allSatisfy { $0.reliabilityPolicyVersion == 3 })
        XCTAssertTrue(report.months.contains { $0.sourceDescription.hasSuffix(" local snapshots") })
        XCTAssertFalse(report.exportText.contains("Private May Song"))
        XCTAssertFalse(report.exportText.contains("Private Artist"))
        XCTAssertTrue(report.exportText.contains("Yearly totals match monthly ledgers: true"))
    }

    func testFreshStoreDiagnosticsUseCurrentReliabilityPolicy() {
        let store = makeStore(named: "diagnostics-fresh-store")

        let report = store.recapDiagnosticsReport(at: date(year: 2026, month: 8, day: 25))

        XCTAssertEqual(report.reliabilityPolicyVersion, 3)
        XCTAssertTrue(report.hasCanonicalMonthLedger)
        XCTAssertTrue(report.yearlyTotalsMatchMonthlyLedgers)
        XCTAssertTrue(report.months.isEmpty)
    }

    func testRepeatedCloudMergeIsIdempotentAndDiagnosticsStayCanonical() {
        let source = makeStore(named: "diagnostics-cloud-source")
        let target = makeStore(named: "diagnostics-cloud-target")
        let baselineDate = date(year: 2026, month: 7, day: 31, hour: 22)
        let latestDate = date(year: 2026, month: 8, day: 20, hour: 12)

        _ = source.record(
            songs: [song(id: 1, title: "Cloud Song", playCount: 40)],
            at: baselineDate,
            reason: .foreground
        )
        _ = source.record(
            songs: [song(id: 1, title: "Cloud Song", playCount: 47)],
            at: latestDate,
            reason: .foreground
        )
        let payloads = source.localSyncPayloads()

        XCTAssertTrue(target.mergeSyncPayloads(payloads, now: latestDate))
        let first = target.recapDiagnosticsReport(at: latestDate)
        XCTAssertFalse(target.mergeSyncPayloads(payloads, now: latestDate))
        let second = target.recapDiagnosticsReport(at: latestDate)

        XCTAssertEqual(first.months, second.months)
        XCTAssertEqual(second.duplicateMonthCount, 0)
        XCTAssertTrue(second.hasCanonicalMonthLedger)
        XCTAssertTrue(second.yearlyTotalsMatchMonthlyLedgers)
        XCTAssertEqual(target.recap(forMonthContaining: latestDate).totalPlayDelta, 7)
    }

    func testMonthBoundaryUsesLocalMidnightNotCanonicalNoon() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountBoundary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "local-midnight-boundary"
        )
        let july = date(year: 2026, month: 7, day: 31, hour: 23)
        let august = date(year: 2026, month: 8, day: 1, hour: 1)

        _ = store.record(songs: [song(id: 1, title: "Boundary", playCount: 100)], at: july, reason: .foreground)
        _ = store.record(songs: [song(id: 1, title: "Boundary", playCount: 104)], at: august, reason: .foreground)

        XCTAssertEqual(store.recap(forMonthContaining: july).totalPlayDelta, 0)
        XCTAssertEqual(store.recap(forMonthContaining: august).totalPlayDelta, 4)
    }

    func testPartialReturnAfterMissedMonthWaitsForComparableRecovery() {
        let store = makeStore(named: "partial-gap-recovery")
        let may = date(year: 2026, month: 5, day: 31, hour: 20)
        let partialJuly = date(year: 2026, month: 7, day: 10, hour: 10)
        let recoveredJuly = date(year: 2026, month: 7, day: 10, hour: 11)
        let fullLibrary = (1...100).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }
        let partialLibrary = (1...10).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 130)
        }
        let recoveredLibrary = (1...100).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 130)
        }

        _ = store.record(songs: fullLibrary, at: may, reason: .foreground)
        let held = store.record(songs: partialLibrary, at: partialJuly, reason: .appLaunch)
        XCTAssertEqual(held.totalPlayDelta, 0)
        XCTAssertTrue(store.reliabilityStatus().isUsingLastReliableUpdate)

        let recovered = store.record(songs: recoveredLibrary, at: recoveredJuly, reason: .foreground)
        XCTAssertEqual(recovered.totalPlayDelta, 0)
        XCTAssertFalse(store.reliabilityStatus().isUsingLastReliableUpdate)
        XCTAssertEqual(store.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 3_000)
        XCTAssertEqual(store.syncedYearlyRecap(for: 2026)?.unattributedPlayDelta, 3_000)
    }

    func testBuddhistCalendarKeepsGregorianMonthIdentity() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountBuddhist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: buddhist,
            deviceIdentifier: "buddhist-calendar"
        )
        let july = date(year: 2026, month: 7, day: 31, hour: 23)
        let august = date(year: 2026, month: 8, day: 2, hour: 1)

        _ = store.record(songs: [song(id: 1, title: "Calendar", playCount: 100)], at: july, reason: .foreground)
        let recap = store.record(songs: [song(id: 1, title: "Calendar", playCount: 104)], at: august, reason: .foreground)

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(recap.totalPlayDelta, 4)
        XCTAssertEqual(gregorian.component(.year, from: recap.monthStart), 2026)
        XCTAssertEqual(gregorian.component(.month, from: recap.monthStart), 8)
        XCTAssertEqual(store.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 4)
        XCTAssertEqual(
            store.syncedYearlyRecap(for: 2026).map { gregorian.component(.year, from: $0.monthStart) },
            2026
        )
    }

    func testDiagnosticsAcceptValidMissedMonthEvidence() {
        let store = makeStore(named: "diagnostics-gap-evidence")
        let may = date(year: 2026, month: 5, day: 31)
        let julyReturn = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 15)

        _ = store.record(songs: [song(id: 1, title: "Private Gap Song", playCount: 100)], at: may, reason: .foreground)
        _ = store.record(songs: [song(id: 1, title: "Private Gap Song", playCount: 130)], at: julyReturn, reason: .appLaunch)
        _ = store.record(songs: [song(id: 1, title: "Private Gap Song", playCount: 135)], at: julyLatest, reason: .foreground)

        let report = store.recapDiagnosticsReport(at: julyLatest)
        XCTAssertEqual(report.months.reduce(0) { $0 + $1.totalPlayDelta }, 5)
        XCTAssertEqual(store.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 35)
        XCTAssertTrue(report.yearlyTotalsMatchMonthlyLedgers)
        XCTAssertEqual(report.unattributedIntervalCount, 1)
        XCTAssertEqual(report.unattributedPlayDelta, 30)
        XCTAssertTrue(report.exportText.contains("Unattributed plays: 30"))
        XCTAssertFalse(report.exportText.contains("Private Gap Song"))
    }

    func testHistoricalMissedGapEvidenceSurvivesRawSnapshotRetention() {
        let store = makeStore(named: "durable-historical-gap")
        let january = date(year: 2024, month: 1, day: 31)
        let marchReturn = date(year: 2024, month: 3, day: 10)
        let marchLatest = date(year: 2024, month: 3, day: 15)

        _ = store.record(songs: [song(id: 1, title: "Historical Gap", playCount: 100)], at: january, reason: .foreground)
        _ = store.record(songs: [song(id: 1, title: "Historical Gap", playCount: 130)], at: marchReturn, reason: .appLaunch)
        _ = store.record(songs: [song(id: 1, title: "Historical Gap", playCount: 135)], at: marchLatest, reason: .foreground)
        XCTAssertEqual(store.syncedYearlyRecap(for: 2024)?.totalPlayDelta, 35)

        _ = store.localSyncPayloads()

        XCTAssertEqual(store.syncedYearlyRecap(for: 2024)?.totalPlayDelta, 35)
        XCTAssertEqual(store.syncedYearlyRecap(for: 2024)?.unattributedPlayDelta, 30)
        let diagnostics = store.recapDiagnosticsReport(at: Date())
        XCTAssertEqual(diagnostics.unattributedIntervalCount, 1)
        XCTAssertEqual(diagnostics.unattributedPlayDelta, 30)
        XCTAssertTrue(diagnostics.yearlyTotalsMatchMonthlyLedgers)
    }

    func testDiagnosticsRejectMissingYearlySummary() {
        let store = makeStore(named: "diagnostics-missing-year")
        let baseline = date(year: 2026, month: 8, day: 1)
        let latest = date(year: 2026, month: 8, day: 2)
        _ = store.record(songs: [song(id: 1, title: "Missing Year", playCount: 10)], at: baseline, reason: .appLaunch)
        _ = store.record(songs: [song(id: 1, title: "Missing Year", playCount: 12)], at: latest, reason: .foreground)
        store.debugRemoveYearlyRecaps()

        XCTAssertFalse(store.recapDiagnosticsReport(at: latest).yearlyTotalsMatchMonthlyLedgers)
    }

    func testMigrationDoesNotPromoteUnrebuildableHistoricalLedgerToPolicyV2() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountHistoricalPolicy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let target = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "historical-policy-target"
        )
        let julyBaseline = date(year: 2026, month: 7, day: 1)
        let julyLatest = date(year: 2026, month: 7, day: 15)
        let augustBaseline = date(year: 2026, month: 8, day: 1)
        _ = target.record(songs: [song(id: 1, title: "Historical", playCount: 100)], at: julyBaseline, reason: .appLaunch)
        let accurate = target.record(songs: [song(id: 1, title: "Historical", playCount: 130)], at: julyLatest, reason: .foreground)
        _ = target.record(songs: [song(id: 1, title: "Historical", playCount: 130)], at: augustBaseline, reason: .foreground)
        let polluted = MonthlyRecap(
            monthStart: accurate.monthStart,
            generatedAt: accurate.generatedAt,
            lastCaptureReason: accurate.lastCaptureReason,
            trackingStart: accurate.trackingStart,
            snapshotCount: accurate.snapshotCount,
            totalPlayDelta: 3_030,
            totalSkipDelta: accurate.totalSkipDelta,
            totalListeningDuration: 3_030 * 180,
            playedSongCount: accurate.playedSongCount,
            listenedArtistCount: accurate.listenedArtistCount,
            newSongCount: accurate.newSongCount,
            topSongs: accurate.topSongs,
            topArtists: accurate.topArtists,
            topAlbums: accurate.topAlbums,
            biggestGainers: accurate.biggestGainers,
            biggestAlbumGainers: accurate.biggestAlbumGainers,
            biggestArtistGainers: accurate.biggestArtistGainers,
            topNewSongs: accurate.topNewSongs
        )
        try target.debugInstallPreCounterReliabilityPolicyRecapMissingListenedArtistCount(polluted)

        let migrated = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "historical-policy-target"
        )
        let julyDiagnostic = try XCTUnwrap(migrated.recapDiagnosticsReport(at: augustBaseline).months.first {
            calendar.recapMonth(containing: $0.monthStart) == 7
        })
        XCTAssertEqual(julyDiagnostic.reliabilityPolicyVersion, 0)
        XCTAssertEqual(migrated.debugYearlyReliabilityPolicyVersion(for: 2026), 0)
        XCTAssertEqual(migrated.recap(forMonthContaining: julyLatest).listenedArtistCount, 1)

        let source = makeStore(named: "historical-policy-source")
        _ = source.record(songs: [song(id: 1, title: "Historical", playCount: 100)], at: julyBaseline, reason: .appLaunch)
        _ = source.record(songs: [song(id: 1, title: "Historical", playCount: 130)], at: julyLatest, reason: .foreground)
        XCTAssertTrue(migrated.mergeSyncPayloads(source.localSyncPayloads(), now: augustBaseline))
        XCTAssertEqual(migrated.recap(forMonthContaining: julyLatest).totalPlayDelta, 30)
    }

    func testReliablePolicyRecapWinsOverLargerLegacyCloudSummary() {
        let store = makeStore(named: "reliable-policy-priority")
        let baselineDate = date(year: 2026, month: 7, day: 31, hour: 22)
        let latestDate = date(year: 2026, month: 8, day: 4, hour: 10)
        _ = store.record(
            songs: [song(id: 1, title: "Reliable", playCount: 100)],
            at: baselineDate,
            reason: .foreground
        )
        let reliable = store.record(
            songs: [song(id: 1, title: "Reliable", playCount: 102)],
            at: latestDate,
            reason: .foreground
        )
        let inflatedLegacy = MonthlyRecap(
            monthStart: reliable.monthStart,
            generatedAt: reliable.generatedAt,
            lastCaptureReason: reliable.lastCaptureReason,
            trackingStart: reliable.trackingStart,
            snapshotCount: reliable.snapshotCount,
            totalPlayDelta: 5_002,
            totalSkipDelta: reliable.totalSkipDelta,
            totalListeningDuration: 5_002 * 180,
            playedSongCount: reliable.playedSongCount,
            listenedArtistCount: reliable.listenedArtistCount,
            newSongCount: reliable.newSongCount,
            topSongs: reliable.topSongs,
            topArtists: reliable.topArtists,
            topAlbums: reliable.topAlbums,
            biggestGainers: reliable.biggestGainers,
            biggestAlbumGainers: reliable.biggestAlbumGainers,
            biggestArtistGainers: reliable.biggestArtistGainers,
            topNewSongs: reliable.topNewSongs
        )

        store.debugInstallSyncedRecapCandidates([
            (inflatedLegacy, nil),
            (reliable, 2)
        ])

        XCTAssertEqual(store.recap(forMonthContaining: latestDate).totalPlayDelta, 2)
        XCTAssertTrue(store.localSyncPayloads().allSatisfy { $0.reliabilityPolicyVersion == 3 })
    }

    func testSparseCurrentPolicyCloudSummaryCannotReplaceDurableLegacyAccumulator() {
        let store = makeStore(named: "durable-cloud-priority")
        let monthStart = date(year: 2026, month: 8, day: 1)
        let durableSong = MonthlyRecap.RankedSong(
            id: 1,
            title: "Durable Month",
            artist: "Artist",
            albumTitle: "Album",
            playDelta: 1_023,
            skipDelta: 0,
            listeningDuration: 1_023 * 180,
            artwork: nil
        )
        let sparseSong = MonthlyRecap.RankedSong(
            id: 1,
            title: "Durable Month",
            artist: "Artist",
            albumTitle: "Album",
            playDelta: 92,
            skipDelta: 0,
            listeningDuration: 92 * 180,
            artwork: nil
        )

        func recap(generatedAt: Date, snapshots: Int, plays: Int, song: MonthlyRecap.RankedSong) -> MonthlyRecap {
            MonthlyRecap(
                monthStart: monthStart,
                generatedAt: generatedAt,
                lastCaptureReason: .foreground,
                trackingStart: monthStart,
                snapshotCount: snapshots,
                totalPlayDelta: plays,
                totalSkipDelta: 0,
                totalListeningDuration: TimeInterval(plays * 180),
                playedSongCount: 1,
                listenedArtistCount: 1,
                newSongCount: 0,
                topSongs: [song],
                topArtists: [],
                topAlbums: [],
                biggestGainers: [],
                biggestAlbumGainers: [],
                biggestArtistGainers: [],
                topNewSongs: []
            )
        }

        let durable = recap(
            generatedAt: date(year: 2026, month: 8, day: 26, hour: 12),
            snapshots: 11,
            plays: 1_023,
            song: durableSong
        )
        let sparse = recap(
            generatedAt: date(year: 2026, month: 8, day: 26, hour: 13),
            snapshots: 3,
            plays: 92,
            song: sparseSong
        )

        store.debugInstallSyncedRecapCandidates([
            (durable, 2),
            (sparse, 3)
        ])

        XCTAssertEqual(store.recap(forMonthContaining: monthStart).totalPlayDelta, 1_023)
        XCTAssertEqual(store.recap(forMonthContaining: monthStart).snapshotCount, 11)
    }

    func testEmptyCurrentPolicyCloudSummaryCannotErasePopulatedLegacyMonth() {
        let store = makeStore(named: "populated-cloud-priority")
        let monthStart = date(year: 2026, month: 7, day: 1)
        let rankedSong = MonthlyRecap.RankedSong(
            id: 1,
            title: "Remembered July",
            artist: "Artist",
            albumTitle: "Album",
            playDelta: 44,
            skipDelta: 0,
            listeningDuration: 44 * 180,
            artwork: nil
        )
        let populated = MonthlyRecap(
            monthStart: monthStart,
            generatedAt: date(year: 2026, month: 7, day: 31, hour: 12),
            lastCaptureReason: .foreground,
            trackingStart: monthStart,
            snapshotCount: 1,
            totalPlayDelta: 44,
            totalSkipDelta: 0,
            totalListeningDuration: 44 * 180,
            playedSongCount: 1,
            listenedArtistCount: 1,
            newSongCount: 0,
            topSongs: [rankedSong],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            biggestAlbumGainers: [],
            biggestArtistGainers: [],
            topNewSongs: []
        )
        let empty = MonthlyRecap(
            monthStart: monthStart,
            generatedAt: date(year: 2026, month: 8, day: 26),
            lastCaptureReason: .foreground,
            trackingStart: monthStart,
            snapshotCount: 1,
            totalPlayDelta: 0,
            totalSkipDelta: 0,
            totalListeningDuration: 0,
            playedSongCount: 0,
            listenedArtistCount: 0,
            newSongCount: 0,
            topSongs: [],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            biggestAlbumGainers: [],
            biggestArtistGainers: [],
            topNewSongs: []
        )

        store.debugInstallSyncedRecapCandidates([
            (populated, 2),
            (empty, 3)
        ])

        XCTAssertEqual(store.recap(forMonthContaining: monthStart).totalPlayDelta, 44)
        XCTAssertEqual(store.recap(forMonthContaining: monthStart).topSongs.first?.title, "Remembered July")
    }

    func testAvailableMonthsExcludeEmptyTrackedBaselineMonths() {
        let store = makeStore(named: "recap-navigation-active-months")
        let mayBaseline = date(year: 2026, month: 5, day: 1)
        let mayLatest = date(year: 2026, month: 5, day: 3)
        let julyBaseline = date(year: 2026, month: 7, day: 1)
        let augustBaseline = date(year: 2026, month: 8, day: 1)
        let augustLatest = date(year: 2026, month: 8, day: 3)

        _ = store.record(
            songs: [song(id: 1, title: "Navigation Song", playCount: 10)],
            at: mayBaseline,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Navigation Song", playCount: 12)],
            at: mayLatest,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Navigation Song", playCount: 12)],
            at: julyBaseline,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Navigation Song", playCount: 12)],
            at: augustBaseline,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Navigation Song", playCount: 15)],
            at: augustLatest,
            reason: .foreground
        )

        let libraryAdditionsOnly = MonthlyRecap(
            monthStart: julyBaseline,
            generatedAt: julyBaseline,
            lastCaptureReason: .appLaunch,
            trackingStart: julyBaseline,
            snapshotCount: 1,
            totalPlayDelta: 0,
            totalSkipDelta: 0,
            totalListeningDuration: 0,
            playedSongCount: 0,
            listenedArtistCount: 0,
            newSongCount: 22,
            topSongs: [],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            biggestAlbumGainers: [],
            biggestArtistGainers: [],
            topNewSongs: []
        )
        store.debugInstallSyncedRecapCandidates([(libraryAdditionsOnly, 3)])

        let presentation = store.cachedRecapPresentation(through: augustLatest)
        let presentedMonths = presentation.availableMonthStarts.map {
            Calendar.current.component(.month, from: $0)
        }
        let directlyAvailableMonths = store.availableMonthStarts(through: augustLatest).map {
            Calendar.current.component(.month, from: $0)
        }

        XCTAssertTrue(presentation.monthlyRecaps.contains {
            Calendar.current.component(.month, from: $0.monthStart) == 7 &&
                $0.hasActivity &&
                !$0.hasListeningActivity
        })
        XCTAssertEqual(presentedMonths, [5, 8])
        XCTAssertEqual(directlyAvailableMonths, [5, 8])
    }

    func testCurrentPolicyCloudHighWaterReconnectsAfterRelaunchWithoutLoweringHistory() {
        let remote = makeStore(named: "current-policy-cloud-high-water")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountCloudHighWaterRepair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let remoteBaseline = date(year: 2026, month: 8, day: 1)
        let remoteLatest = date(year: 2026, month: 8, day: 4)
        let firstLocalCapture = date(year: 2026, month: 8, day: 5)
        let nextLocalCapture = date(year: 2026, month: 8, day: 6)

        _ = remote.record(
            songs: [song(id: 1, title: "Cloud History", playCount: 100)],
            at: remoteBaseline,
            reason: .appLaunch
        )
        let highWater = remote.record(
            songs: [song(id: 1, title: "Cloud History", playCount: 474)],
            at: remoteLatest,
            reason: .foreground
        )
        XCTAssertEqual(highWater.totalPlayDelta, 374)

        let target = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "replacement-phone"
        )
        XCTAssertTrue(target.mergeSyncPayloads(remote.syncPayloads(), now: remoteLatest))
        let anchored = target.record(
            songs: [song(id: 2, title: "Local History", playCount: 50)],
            at: firstLocalCapture,
            reason: .appLaunch
        )
        XCTAssertEqual(anchored.totalPlayDelta, 374)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "replacement-phone"
        )
        let repaired = relaunched.record(
            songs: [song(id: 2, title: "Local History", playCount: 51)],
            at: nextLocalCapture,
            reason: .foreground
        )

        XCTAssertEqual(repaired.totalPlayDelta, 375)
        XCTAssertEqual(relaunched.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 375)
    }

    func testMonthIdentityMigrationCollapsesTimezoneVariantsWithoutSummingThem() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountMonthIdentityRepair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "month-identity-repair"
        )

        func legacyRecap(monthStart: Date, generatedAt: Date, plays: Int) -> MonthlyRecap {
            let rankedSong = MonthlyRecap.RankedSong(
                id: 1,
                title: "Timezone Song",
                artist: "Artist",
                albumTitle: "Album",
                playDelta: plays,
                skipDelta: 0,
                listeningDuration: TimeInterval(plays * 180),
                artwork: nil
            )
            return MonthlyRecap(
                monthStart: monthStart,
                generatedAt: generatedAt,
                lastCaptureReason: .foreground,
                trackingStart: monthStart,
                snapshotCount: 2,
                totalPlayDelta: plays,
                totalSkipDelta: 0,
                totalListeningDuration: TimeInterval(plays * 180),
                playedSongCount: 1,
                listenedArtistCount: 1,
                newSongCount: 0,
                topSongs: [rankedSong],
                topArtists: [],
                topAlbums: [],
                biggestGainers: [],
                topNewSongs: []
            )
        }

        store.debugInstallPreMonthIdentityPolicyRecaps([
            legacyRecap(
                monthStart: date(year: 2026, month: 7, day: 31, hour: 21),
                generatedAt: date(year: 2026, month: 8, day: 4),
                plays: 76
            ),
            legacyRecap(
                monthStart: date(year: 2026, month: 8, day: 1, hour: 7),
                generatedAt: date(year: 2026, month: 8, day: 20),
                plays: 90
            )
        ])

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "month-identity-repair"
        )
        let august = relaunched.recap(forMonthContaining: date(year: 2026, month: 8, day: 25))
        let presentation = relaunched.cachedRecapPresentation(through: date(year: 2026, month: 8, day: 25))

        XCTAssertEqual(august.totalPlayDelta, 90)
        XCTAssertEqual(relaunched.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 90)
        XCTAssertEqual(presentation.monthlyRecaps.count, 1)
        XCTAssertEqual(presentation.availableMonthStarts.count, 1)
        XCTAssertTrue(relaunched.localSyncPayloads().allSatisfy { $0.reliabilityPolicyVersion == 3 })
    }

    func testCounterReliabilityMigrationKeepsPersistedMonthAcrossTimezoneBoundary() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountTimezoneBoundaryRepair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(secondsFromGMT: 14 * 60 * 60)!
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let julyLocalBaseline = utc.date(from: DateComponents(
            timeZone: utc.timeZone,
            year: 2026,
            month: 7,
            day: 31,
            hour: 9
        ))!
        let augustLocalCapture = utc.date(from: DateComponents(
            timeZone: utc.timeZone,
            year: 2026,
            month: 7,
            day: 31,
            hour: 11
        ))!
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: sourceCalendar,
            deviceIdentifier: "timezone-boundary"
        )
        _ = source.record(
            songs: [song(id: 1, title: "Boundary", playCount: 10)],
            at: julyLocalBaseline,
            reason: .foreground
        )
        let accurateAugust = source.record(
            songs: [song(id: 1, title: "Boundary", playCount: 15)],
            at: augustLocalCapture,
            reason: .foreground
        )
        XCTAssertEqual(accurateAugust.totalPlayDelta, 5)
        let pollutedAugust = MonthlyRecap(
            monthStart: accurateAugust.monthStart,
            generatedAt: accurateAugust.generatedAt,
            lastCaptureReason: accurateAugust.lastCaptureReason,
            trackingStart: accurateAugust.trackingStart,
            snapshotCount: accurateAugust.snapshotCount,
            totalPlayDelta: 500,
            totalSkipDelta: accurateAugust.totalSkipDelta,
            totalListeningDuration: 500 * 180,
            playedSongCount: accurateAugust.playedSongCount,
            listenedArtistCount: accurateAugust.listenedArtistCount,
            newSongCount: accurateAugust.newSongCount,
            topSongs: accurateAugust.topSongs,
            topArtists: accurateAugust.topArtists,
            topAlbums: accurateAugust.topAlbums,
            biggestGainers: accurateAugust.biggestGainers,
            biggestAlbumGainers: accurateAugust.biggestAlbumGainers,
            biggestArtistGainers: accurateAugust.biggestArtistGainers,
            topNewSongs: accurateAugust.topNewSongs
        )
        source.debugInstallPreCounterReliabilityPolicyRecap(pollutedAugust)

        var destinationCalendar = Calendar(identifier: .gregorian)
        destinationCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 60 * 60)!
        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: destinationCalendar,
            deviceIdentifier: "timezone-boundary"
        )
        let augustIdentity = sourceCalendar.startOfMonth(containing: augustLocalCapture)
        XCTAssertEqual(relaunched.recap(forMonthContaining: augustIdentity).totalPlayDelta, 500)
        XCTAssertEqual(relaunched.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 500)
        XCTAssertEqual(relaunched.cachedRecapSummaries().filter { $0.totalPlayDelta > 0 }.count, 1)
    }

    func testCounterReliabilityMigrationRepairsInflatedActiveMonthLedger() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountCounterRepair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "counter-repair"
        )
        let baselineDate = date(year: 2026, month: 7, day: 31, hour: 22)
        let latestDate = date(year: 2026, month: 8, day: 4, hour: 10)
        let baselineSongs = (1...30).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }
        let latestSongs = (1...30).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 101)
        }

        _ = store.record(songs: baselineSongs, at: baselineDate, reason: .foreground)
        let correct = store.record(songs: latestSongs, at: latestDate, reason: .foreground)
        XCTAssertEqual(correct.totalPlayDelta, 30)

        let polluted = MonthlyRecap(
            monthStart: correct.monthStart,
            generatedAt: correct.generatedAt,
            lastCaptureReason: correct.lastCaptureReason,
            trackingStart: correct.trackingStart,
            snapshotCount: correct.snapshotCount,
            totalPlayDelta: 3_030,
            totalSkipDelta: correct.totalSkipDelta,
            totalListeningDuration: 3_030 * 180,
            playedSongCount: correct.playedSongCount,
            listenedArtistCount: correct.listenedArtistCount,
            newSongCount: correct.newSongCount,
            topSongs: correct.topSongs,
            topArtists: correct.topArtists,
            topAlbums: correct.topAlbums,
            biggestGainers: correct.biggestGainers,
            biggestAlbumGainers: correct.biggestAlbumGainers,
            biggestArtistGainers: correct.biggestArtistGainers,
            topNewSongs: correct.topNewSongs
        )
        store.debugInstallPreCounterReliabilityPolicyRecap(polluted)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "counter-repair"
        )
        let repaired = relaunched.recap(forMonthContaining: latestDate)
        XCTAssertEqual(repaired.totalPlayDelta, 30)
        XCTAssertEqual(repaired.topSongs.count, 30)
        XCTAssertTrue(repaired.topSongs.allSatisfy { $0.playDelta == 1 })
        XCTAssertEqual(relaunched.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 30)
    }

    func testCounterReliabilityMigrationPreservesDurableAccumulatorWhenRawHistoryWasCompacted() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountCompactedAccumulator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "compacted-accumulator"
        )
        let baseline = date(year: 2026, month: 8, day: 1)
        let returnAfterGap = date(year: 2026, month: 8, day: 24)
        let latest = date(year: 2026, month: 8, day: 26)

        _ = store.record(
            songs: [song(id: 1, title: "Durable Month", playCount: 100)],
            at: baseline,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Durable Month", playCount: 102)],
            at: returnAfterGap,
            reason: .foreground
        )
        let sparse = store.record(
            songs: [song(id: 1, title: "Durable Month", playCount: 103)],
            at: latest,
            reason: .foreground
        )
        XCTAssertEqual(sparse.totalPlayDelta, 3)

        let durableSong = MonthlyRecap.RankedSong(
            id: 1,
            title: "Durable Month",
            artist: "Artist",
            albumTitle: "Album",
            playDelta: 1_023,
            skipDelta: 0,
            listeningDuration: 1_023 * 180,
            artwork: nil
        )
        let durable = MonthlyRecap(
            monthStart: sparse.monthStart,
            generatedAt: sparse.generatedAt,
            lastCaptureReason: sparse.lastCaptureReason,
            trackingStart: baseline,
            snapshotCount: 11,
            totalPlayDelta: 1_023,
            totalSkipDelta: 0,
            totalListeningDuration: 1_023 * 180,
            playedSongCount: 1,
            listenedArtistCount: 1,
            newSongCount: 0,
            topSongs: [durableSong],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            biggestAlbumGainers: [],
            biggestArtistGainers: [],
            topNewSongs: []
        )
        store.debugInstallPreCounterReliabilityPolicyRecap(durable)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "compacted-accumulator"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: latest).totalPlayDelta, 1_023)
        XCTAssertEqual(relaunched.recap(forMonthContaining: latest).snapshotCount, 11)
        XCTAssertEqual(relaunched.debugYearlyReliabilityPolicyVersion(for: 2026), 3)
        XCTAssertTrue(relaunched.localSyncPayloads().allSatisfy { $0.reliabilityPolicyVersion == 3 })
    }

    func testCounterReliabilityMigrationPreservesHistoricalRecapWhenStaleDeviceHasOnlyBaseline() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountStaleDeviceMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "current-phone"
        )
        let staleStore = makeStore(named: "stale-ipad")
        let julyDate = date(year: 2026, month: 7, day: 20)
        _ = staleStore.record(
            songs: [song(id: 9, title: "Stale Baseline", playCount: 400)],
            at: julyDate,
            reason: .foreground
        )
        XCTAssertTrue(store.mergeSyncPayloads(staleStore.syncPayloads(), now: julyDate))

        let augustBaseline = date(year: 2026, month: 8, day: 1)
        let augustLatest = date(year: 2026, month: 8, day: 4)
        _ = store.record(
            songs: [song(id: 1, title: "Current", playCount: 100)],
            at: augustBaseline,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Current", playCount: 110)],
            at: augustLatest,
            reason: .foreground
        )

        let historicalJuly = MonthlyRecap(
            monthStart: calendar.startOfMonth(containing: julyDate),
            generatedAt: julyDate,
            lastCaptureReason: .foreground,
            trackingStart: date(year: 2026, month: 7, day: 1),
            snapshotCount: 8,
            totalPlayDelta: 44,
            totalSkipDelta: 0,
            totalListeningDuration: 44 * 180,
            playedSongCount: 1,
            listenedArtistCount: 1,
            newSongCount: 0,
            topSongs: [],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            biggestAlbumGainers: [],
            biggestArtistGainers: [],
            topNewSongs: []
        )
        store.debugInstallPreCounterReliabilityPolicyRecap(historicalJuly)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "current-phone"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: julyDate).totalPlayDelta, 44)
        XCTAssertEqual(relaunched.recap(forMonthContaining: augustLatest).totalPlayDelta, 10)
        XCTAssertEqual(relaunched.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 54)
    }

    func testCounterReliabilityMigrationPreservesSummaryOnlyMonthsBesidePartialLedgers() {
        let ledgerSource = makeStore(named: "partial-policy-ledger-source")
        let summarySource = makeStore(named: "partial-policy-summary-source")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountPartialPolicy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "partial-policy-target"
        )
        _ = ledgerSource.record(
            songs: [song(id: 1, title: "August", playCount: 10)],
            at: date(year: 2026, month: 8, day: 1),
            reason: .foreground
        )
        let august = ledgerSource.record(
            songs: [song(id: 1, title: "August", playCount: 14)],
            at: date(year: 2026, month: 8, day: 3),
            reason: .foreground
        )
        _ = summarySource.record(
            songs: [song(id: 2, title: "May", playCount: 20)],
            at: date(year: 2026, month: 5, day: 1),
            reason: .foreground
        )
        let may = summarySource.record(
            songs: [song(id: 2, title: "May", playCount: 27)],
            at: date(year: 2026, month: 5, day: 3),
            reason: .foreground
        )
        target.debugInstallPreCounterReliabilityPolicyEvidence(
            monthlyLedgerRecaps: [august],
            summaryOnlyRecaps: [may]
        )

        let reloaded = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "partial-policy-target"
        )
        XCTAssertEqual(reloaded.recap(forMonthContaining: date(year: 2026, month: 5, day: 3)).totalPlayDelta, 7)
        XCTAssertEqual(reloaded.recap(forMonthContaining: date(year: 2026, month: 8, day: 3)).totalPlayDelta, 4)
        XCTAssertEqual(reloaded.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 11)
    }

    func testCounterReliabilityMigrationDoesNotDowngradeDurableMonthFromAnotherRepairableStream() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountMixedStreamMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let julyBaseline = date(year: 2026, month: 7, day: 2)
        let julyLatest = date(year: 2026, month: 7, day: 20)
        let target = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "durable-phone"
        )
        _ = target.record(
            songs: [song(id: 1, title: "Durable Baseline", playCount: 400)],
            at: julyLatest,
            reason: .foreground
        )

        let repairable = makeStore(named: "lower-repairable-stream")
        _ = repairable.record(
            songs: [song(id: 2, title: "Lower Evidence", playCount: 100)],
            at: julyBaseline,
            reason: .foreground
        )
        _ = repairable.record(
            songs: [song(id: 2, title: "Lower Evidence", playCount: 110)],
            at: julyLatest,
            reason: .foreground
        )
        XCTAssertTrue(target.mergeSyncPayloads(repairable.syncPayloads(), now: julyLatest))

        let durableSource = makeStore(named: "durable-history-source")
        _ = durableSource.record(
            songs: [song(id: 3, title: "Durable History", playCount: 100)],
            at: julyBaseline,
            reason: .foreground
        )
        let durableHistorical = durableSource.record(
            songs: [song(id: 3, title: "Durable History", playCount: 144)],
            at: julyLatest,
            reason: .foreground
        )
        target.debugInstallPreCounterReliabilityPolicyRecap(durableHistorical)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "durable-phone"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: julyLatest).totalPlayDelta, 44)
        XCTAssertEqual(relaunched.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 44)
    }

    func testCounterReliabilityMigrationRepairsHistoricalStaleDeviceWhenComparableEvidenceSurvives() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountHistoricalRepair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "current-phone"
        )
        let staleStore = makeStore(named: "historical-ipad")
        let julyBaseline = date(year: 2026, month: 7, day: 2)
        let julyLatest = date(year: 2026, month: 7, day: 20)
        _ = staleStore.record(
            songs: [song(id: 9, title: "Historical", playCount: 400)],
            at: julyBaseline,
            reason: .foreground
        )
        let accurateJuly = staleStore.record(
            songs: [song(id: 9, title: "Historical", playCount: 405)],
            at: julyLatest,
            reason: .foreground
        )
        XCTAssertTrue(store.mergeSyncPayloads(staleStore.syncPayloads(), now: julyLatest))
        _ = store.record(
            songs: [song(id: 1, title: "Current", playCount: 100)],
            at: date(year: 2026, month: 8, day: 1),
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Current", playCount: 110)],
            at: date(year: 2026, month: 8, day: 4),
            reason: .foreground
        )
        let polluted = MonthlyRecap(
            monthStart: accurateJuly.monthStart,
            generatedAt: accurateJuly.generatedAt,
            lastCaptureReason: accurateJuly.lastCaptureReason,
            trackingStart: accurateJuly.trackingStart,
            snapshotCount: accurateJuly.snapshotCount,
            totalPlayDelta: 500,
            totalSkipDelta: accurateJuly.totalSkipDelta,
            totalListeningDuration: 500 * 180,
            playedSongCount: accurateJuly.playedSongCount,
            listenedArtistCount: accurateJuly.listenedArtistCount,
            newSongCount: accurateJuly.newSongCount,
            topSongs: accurateJuly.topSongs,
            topArtists: accurateJuly.topArtists,
            topAlbums: accurateJuly.topAlbums,
            biggestGainers: accurateJuly.biggestGainers,
            biggestAlbumGainers: accurateJuly.biggestAlbumGainers,
            biggestArtistGainers: accurateJuly.biggestArtistGainers,
            topNewSongs: accurateJuly.topNewSongs
        )
        store.debugInstallPreCounterReliabilityPolicyRecap(polluted)

        let relaunched = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "current-phone"
        )
        XCTAssertEqual(relaunched.recap(forMonthContaining: julyLatest).totalPlayDelta, 5)
        XCTAssertEqual(relaunched.recap(forMonthContaining: date(year: 2026, month: 8, day: 4)).totalPlayDelta, 10)
    }

    func testImplausibleLocalStreamDoesNotOverridePlausibleRemoteRecap() {
        let phoneStore = makeStore(named: "phone-plausible")
        let iPadStore = makeStore(named: "ipad-implausible")
        let iPadBaselineDate = date(year: 2026, month: 5, day: 1, hour: 0)
        let phoneBaselineDate = date(year: 2026, month: 5, day: 2, hour: 0)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 0)

        _ = iPadStore.record(
            songs: [song(id: 1, title: "Polluted iPad Song", playCount: 0)],
            at: iPadBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 1, title: "Polluted iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )
        _ = phoneStore.record(
            songs: [song(id: 2, title: "Real Phone Song", playCount: 100)],
            at: phoneBaselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 2, title: "Real Phone Song", playCount: 433)],
            at: latestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-plausible")
        XCTAssertTrue(targetStore.mergeSyncPayloads(iPadStore.syncPayloads() + phoneStore.syncPayloads(), now: latestDate))

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 333)
        XCTAssertEqual(Int(recap.totalListeningDuration / 60), 999)
        XCTAssertEqual(recap.topSongs.first?.title, "Real Phone Song")
    }

    func testLateRemoteBaselineCanStillRepresentMonthToDateRecap() {
        let phoneStore = makeStore(named: "phone-late-baseline")
        let iPadStore = makeStore(named: "ipad-inflated-late-baseline")
        let monthStart = date(year: 2026, month: 5, day: 1, hour: 0)
        let baselineDate = date(year: 2026, month: 5, day: 8, hour: 10)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 11)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Real Phone Song", playCount: 100)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Real Phone Song", playCount: 433)],
            at: latestDate,
            reason: .foreground
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Polluted iPad Song", playCount: 0)],
            at: monthStart,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Polluted iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-late-baseline")
        XCTAssertTrue(targetStore.mergeSyncPayloads(iPadStore.syncPayloads() + phoneStore.syncPayloads(), now: latestDate))

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 333)
        XCTAssertEqual(Int(recap.totalListeningDuration / 60), 999)
        XCTAssertEqual(recap.topSongs.first?.title, "Real Phone Song")
    }

    func testReliableRankingStreamWinsOverAggregateOnlyStream() {
        let reliableStore = makeStore(named: "reliable-ranking")
        let aggregateOnlyStore = makeStore(named: "aggregate-only-ranking")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)

        _ = aggregateOnlyStore.record(
            songs: [song(id: 1, title: "Old Identity", playCount: 1_000)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = aggregateOnlyStore.record(
            songs: [song(id: 2, title: "New Identity", playCount: 1_300)],
            at: latestDate,
            reason: .foreground
        )

        _ = reliableStore.record(
            songs: [song(id: 3, title: "Reliable Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = reliableStore.record(
            songs: [song(id: 3, title: "Reliable Song", playCount: 14)],
            at: latestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-ranking-coverage")
        XCTAssertTrue(targetStore.mergeSyncPayloads(
            aggregateOnlyStore.syncPayloads() + reliableStore.syncPayloads(),
            now: latestDate
        ))

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.topSongs.first?.title, "Reliable Song")
        XCTAssertEqual(recap.totalPlayDelta, 4)
    }

    func testTrimmedSyncPayloadPreservesFullAggregateTotals() {
        let phoneStore = makeStore(named: "phone-large")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let latestDate = date(year: 2026, month: 5, day: 5, hour: 12)
        let largeSuffix = String(repeating: "x", count: 1_000)
        let baselineSongs = (1...1_200).map {
            song(
                id: UInt64($0),
                title: "Song \($0) \(largeSuffix)",
                artist: "Artist \($0)",
                playCount: 10,
                artistPersistentID: UInt64($0)
            )
        }
        let latestSongs = (1...1_200).map {
            song(
                id: UInt64($0),
                title: "Song \($0) \(largeSuffix)",
                artist: "Artist \($0)",
                playCount: 11,
                artistPersistentID: UInt64($0)
            )
        }

        _ = phoneStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        let sourceRecap = phoneStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = phoneStore.localSyncPayloads()
        XCTAssertLessThanOrEqual(payloads.map(\.encodedSnapshot.count).max() ?? 0, 250_000)

        let iPadStore = makeStore(named: "ipad-large")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(payloads, now: latestDate))

        let iPadRecap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(sourceRecap.totalPlayDelta, 1_200)
        XCTAssertEqual(iPadRecap.totalPlayDelta, sourceRecap.totalPlayDelta)
        XCTAssertEqual(iPadRecap.totalListeningDuration, sourceRecap.totalListeningDuration)
        XCTAssertEqual(iPadRecap.playedSongCount, sourceRecap.playedSongCount)
        XCTAssertEqual(sourceRecap.listenedArtistCount, 1_200)
        XCTAssertEqual(iPadRecap.listenedArtistCount, sourceRecap.listenedArtistCount)
        XCTAssertLessThan(iPadRecap.topSongs.count, baselineSongs.count)
        XCTAssertLessThan(iPadRecap.topArtists.count, sourceRecap.listenedArtistCount)
    }

    func testHigherUserRecapTotalsWinOverLaterLowerDeviceBaseline() {
        let phoneStore = makeStore(named: "phone-synced-source")
        let iPadStore = makeStore(named: "ipad-user-source")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let phoneLatestDate = date(year: 2026, month: 5, day: 10, hour: 6)
        let iPadBaselineDate = date(year: 2026, month: 5, day: 8, hour: 21)
        let iPadLatestDate = date(year: 2026, month: 5, day: 10, hour: 6)
        let largeSuffix = String(repeating: "x", count: 1_000)
        let phoneBaselineSongs = (1...1_200).map {
            song(id: UInt64($0), title: "Phone Song \($0) \(largeSuffix)", playCount: 100)
        }
        let phoneLatestSongs = phoneBaselineSongs.enumerated().map { index, baselineSong in
            let extraPlay = index < 379 ? 1 : 0
            return song(
                id: baselineSong.id,
                title: baselineSong.title,
                playCount: baselineSong.playCount + extraPlay
            )
        }
        let iPadBaselineSongs = (1...1_200).map {
            song(id: UInt64(10_000 + $0), title: "iPad Song \($0)", playCount: 100)
        }
        let iPadLatestSongs = iPadBaselineSongs.enumerated().map { index, baselineSong in
            let extraPlay = index < 65 ? 1 : 0
            return song(
                id: baselineSong.id,
                title: baselineSong.title,
                playCount: baselineSong.playCount + extraPlay
            )
        }

        _ = phoneStore.record(songs: phoneBaselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = phoneStore.record(songs: phoneLatestSongs, at: phoneLatestDate, reason: .foreground)
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phoneStore.localSyncPayloads(), now: phoneLatestDate))
        _ = iPadStore.record(songs: iPadBaselineSongs, at: iPadBaselineDate, reason: .manualRefresh)
        _ = iPadStore.record(songs: iPadLatestSongs, at: iPadLatestDate, reason: .foreground)

        let recap = iPadStore.recap(forMonthContaining: iPadLatestDate)
        XCTAssertEqual(recap.totalPlayDelta, 379)
    }

    func testTrimmedLocalSyncPayloadPreservesChangedSongRankings() {
        let phoneStore = makeStore(named: "phone-large-ranking")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let largeSuffix = String(repeating: "x", count: 1_000)
        var baselineSongs: [TopSong] = []
        for index in 1...1_200 {
            let isRecentFavorite = index == 1_200
            let title = isRecentFavorite ? "Actual Recent Favorite \(largeSuffix)" : "Song \(index) \(largeSuffix)"
            let playCount = isRecentFavorite ? 0 : 1_000 - min(index, 999)
            baselineSongs.append(song(id: UInt64(index), title: title, playCount: playCount))
        }
        let latestSongs = baselineSongs.map { baselineSong -> TopSong in
            guard baselineSong.id == 1_200 else { return baselineSong }
            return song(id: baselineSong.id, title: baselineSong.title, playCount: 25)
        }

        _ = phoneStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = phoneStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = phoneStore.localSyncPayloads()
        XCTAssertLessThanOrEqual(payloads.map(\.encodedSnapshot.count).max() ?? 0, 250_000)

        let iPadStore = makeStore(named: "ipad-large-ranking")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(payloads, now: latestDate))

        let iPadRecap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(iPadRecap.totalPlayDelta, 25)
        XCTAssertEqual(iPadRecap.topSongs.first?.title, "Actual Recent Favorite \(largeSuffix)")
    }

    func testTrimmedLocalSyncPayloadPreservesNewSongRankings() {
        let phoneStore = makeStore(named: "phone-new-ranking")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let newSongDate = date(year: 2026, month: 5, day: 7, hour: 8)
        let largeSuffix = String(repeating: "x", count: 1_000)
        var baselineSongs: [TopSong] = []
        for index in 1...1_200 {
            baselineSongs.append(
                song(
                    id: UInt64(index),
                    title: "Catalog Song \(index) \(largeSuffix)",
                    playCount: 1_000 - min(index, 999)
                )
            )
        }
        var latestSongs = baselineSongs
        latestSongs.append(
            song(
                id: 9_001,
                title: "Sabrina New Song \(largeSuffix)",
                playCount: 12,
                dateAdded: newSongDate
            )
        )

        _ = phoneStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = phoneStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = phoneStore.localSyncPayloads()
        XCTAssertLessThanOrEqual(payloads.map(\.encodedSnapshot.count).max() ?? 0, 250_000)

        let iPadStore = makeStore(named: "ipad-new-ranking")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(payloads, now: latestDate))

        let iPadRecap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(iPadRecap.topNewSongs.first?.title, "Sabrina New Song \(largeSuffix)")
        XCTAssertEqual(iPadRecap.topNewSongs.first?.playDelta, 12)
    }

    func testSyncPayloadRecapSummariesRemainLegacyMonthlyArray() throws {
        let sourceStore = makeStore(named: "legacy-monthly-summary")
        let baselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)

        _ = sourceStore.record(
            songs: [song(id: 1, title: "Legacy Compatible Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = sourceStore.record(
            songs: [song(id: 1, title: "Legacy Compatible Song", playCount: 15)],
            at: latestDate,
            reason: .foreground
        )

        let payload = try XCTUnwrap(sourceStore.localSyncPayloads().first { $0.encodedRecaps != nil })
        let encodedRecaps = try XCTUnwrap(payload.encodedRecaps)
        let legacyRecaps = try playCountDecoder.decode([LegacySyncedMonthlyRecap].self, from: encodedRecaps)

        XCTAssertNotNil(payload.encodedYearlyRecaps)
        XCTAssertEqual(legacyRecaps.count, 1)
        XCTAssertEqual(legacyRecaps.first?.totalPlayDelta, 5)
        XCTAssertEqual(legacyRecaps.first?.topSongs.first?.title, "Legacy Compatible Song")
    }

    func testSeparateYearlyRecapSummaryMergesIntoFreshStore() {
        let sourceStore = makeStore(named: "yearly-summary-source")
        let targetStore = makeStore(named: "yearly-summary-target")
        let baselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let newSongDate = date(year: 2026, month: 5, day: 7, hour: 8)
        let baselineSongs = (1...260).map {
            song(id: UInt64($0), title: "Existing Song \($0)", playCount: 10)
        }
        var latestSongs = baselineSongs.map {
            song(id: $0.id, title: $0.title, playCount: $0.playCount + 1)
        }
        latestSongs.append(
            song(
                id: 9_001,
                title: "Low Delta New Song",
                playCount: 1,
                dateAdded: newSongDate
            )
        )

        _ = sourceStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = sourceStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = sourceStore.localSyncPayloads()
        XCTAssertTrue(payloads.contains { $0.encodedRecaps != nil })
        XCTAssertTrue(payloads.contains { $0.encodedYearlyRecaps != nil })
        XCTAssertTrue(targetStore.mergeSyncPayloads(payloads, now: latestDate))

        let yearlyRecap = targetStore.syncedYearlyRecap(for: 2026)
        XCTAssertEqual(yearlyRecap?.playedSongCount, 261)
        XCTAssertEqual(yearlyRecap?.topSongs.count, 250)
        XCTAssertEqual(yearlyRecap?.topNewSongs.first?.title, "Low Delta New Song")
    }

    func testLegacyPhoneBaselineBridgesToCurrentPhoneStreamForConsistentRecap() {
        let phoneStore = makeStore(named: "current-phone")
        let iPadStore = makeStore(named: "polluted-ipad")
        let targetStore = makeStore(named: "target-consistent")
        let legacyBaselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let currentPhoneBaselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let sabrinaDate = date(year: 2026, month: 5, day: 6, hour: 8)

        let legacyBaseline = recapFixtureSongs(
            climberPlayCount: 10,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let currentPhoneBaseline = recapFixtureSongs(
            climberPlayCount: 25,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        var latestPhoneSongs = recapFixtureSongs(
            climberPlayCount: 45,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        latestPhoneSongs.append(song(
            id: 9_001,
            title: "Sabrina New Song",
            playCount: 12,
            dateAdded: sabrinaDate
        ))

        _ = phoneStore.debugRecordLegacySnapshot(
            songs: legacyBaseline,
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: currentPhoneBaseline,
            at: currentPhoneBaselineDate,
            reason: .foreground
        )
        let phoneRecap = phoneStore.record(
            songs: latestPhoneSongs,
            at: latestDate,
            reason: .foreground
        )

        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 0)],
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )

        XCTAssertEqual(phoneRecap.totalPlayDelta, 47)
        XCTAssertEqual(phoneRecap.topNewSongs.first?.title, "Sabrina New Song")
        XCTAssertEqual(phoneRecap.biggestGainers.first?.title, "Climber")

        XCTAssertTrue(targetStore.mergeSyncPayloads(
            iPadStore.syncPayloads() + phoneStore.localSyncPayloads(),
            now: latestDate
        ))

        let targetRecap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(targetRecap.totalPlayDelta, phoneRecap.totalPlayDelta)
        XCTAssertEqual(targetRecap.totalListeningDuration, phoneRecap.totalListeningDuration)
        XCTAssertEqual(targetRecap.topSongs.map(\.title), phoneRecap.topSongs.map(\.title))
        XCTAssertEqual(targetRecap.biggestGainers.map(\.title), phoneRecap.biggestGainers.map(\.title))
        XCTAssertEqual(targetRecap.topNewSongs.map(\.title), phoneRecap.topNewSongs.map(\.title))
    }

    func testCanonicalRecapIsIndependentOfPayloadMergeOrder() {
        let phoneStore = makeStore(named: "phone-order")
        let iPadStore = makeStore(named: "ipad-order")
        let firstTargetStore = makeStore(named: "target-order-first")
        let secondTargetStore = makeStore(named: "target-order-second")
        let legacyBaselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let currentPhoneBaselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let sabrinaDate = date(year: 2026, month: 5, day: 6, hour: 8)

        _ = phoneStore.debugRecordLegacySnapshot(
            songs: recapFixtureSongs(
                climberPlayCount: 10,
                otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
            ),
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: recapFixtureSongs(
                climberPlayCount: 25,
                otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
            ),
            at: currentPhoneBaselineDate,
            reason: .foreground
        )
        var latestPhoneSongs = recapFixtureSongs(
            climberPlayCount: 45,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        latestPhoneSongs.append(song(
            id: 9_001,
            title: "Sabrina New Song",
            playCount: 12,
            dateAdded: sabrinaDate
        ))
        _ = phoneStore.record(songs: latestPhoneSongs, at: latestDate, reason: .foreground)

        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 0)],
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )

        let phonePayloads = phoneStore.localSyncPayloads()
        let iPadPayloads = iPadStore.syncPayloads()
        XCTAssertTrue(firstTargetStore.mergeSyncPayloads(phonePayloads + iPadPayloads, now: latestDate))
        XCTAssertTrue(secondTargetStore.mergeSyncPayloads(iPadPayloads + phonePayloads, now: latestDate))

        let firstRecap = firstTargetStore.recap(forMonthContaining: latestDate)
        let secondRecap = secondTargetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(firstRecap, secondRecap)
        XCTAssertEqual(firstRecap.totalPlayDelta, 47)
        XCTAssertEqual(firstRecap.topNewSongs.first?.title, "Sabrina New Song")
        XCTAssertEqual(firstRecap.biggestGainers.first?.title, "Climber")
    }

    func testDuplicateTrimmedBaselineDoesNotOverrideFullBaselineCopy() {
        let targetStore = makeStore(named: "full-plus-trimmed-target")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let baselineSongs = recapFixtureSongs(
            climberPlayCount: 1,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let trimmedBaselineSongs = Array(baselineSongs.prefix(5))
        let latestSongs = baselineSongs.map { baselineSong -> TopSong in
            guard baselineSong.id == 100 else { return baselineSong }
            return song(id: baselineSong.id, title: baselineSong.title, playCount: 85)
        }

        _ = targetStore.debugRecordLegacySnapshot(
            songs: baselineSongs,
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = targetStore.debugRecordLegacySnapshot(
            songs: trimmedBaselineSongs,
            at: baselineDate,
            reason: .manualRefresh,
            scannedSongCount: baselineSongs.count,
            aggregateSongs: baselineSongs
        )
        _ = targetStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.topSongs.first?.title, "Climber")
        XCTAssertEqual(recap.topSongs.first?.playDelta, 84)
        XCTAssertEqual(recap.biggestGainers.first?.title, "Climber")
    }

    func testLocalSyncPayloadsCanonicalizeDuplicateSnapshotMoments() {
        let store = makeStore(named: "canonical-local-sync")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let baselineSongs = recapFixtureSongs(
            climberPlayCount: 1,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let trimmedBaselineSongs = Array(baselineSongs.prefix(5))
        let latestSongs = baselineSongs.map { baselineSong -> TopSong in
            guard baselineSong.id == 100 else { return baselineSong }
            return song(id: baselineSong.id, title: baselineSong.title, playCount: 85)
        }

        _ = store.debugRecordLegacySnapshot(
            songs: baselineSongs,
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.debugRecordLegacySnapshot(
            songs: trimmedBaselineSongs,
            at: baselineDate,
            reason: .manualRefresh,
            scannedSongCount: baselineSongs.count,
            aggregateSongs: baselineSongs
        )
        _ = store.record(songs: latestSongs, at: latestDate, reason: .foreground)

        XCTAssertEqual(store.localSyncPayloads().count, 2)
    }

    func testMergeSyncPayloadsCanonicalizesDuplicateSnapshotMoments() {
        let fullSourceStore = makeStore(named: "full-source")
        let trimmedSourceStore = makeStore(named: "trimmed-source")
        let targetStore = makeStore(named: "canonical-merge-target")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let baselineSongs = recapFixtureSongs(
            climberPlayCount: 1,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
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

        XCTAssertTrue(targetStore.mergeSyncPayloads(
            fullSourceStore.syncPayloads() + trimmedSourceStore.syncPayloads(),
            now: baselineDate
        ))
        XCTAssertEqual(targetStore.syncPayloads().count, 1)
    }

    func testNoisyExistingCounterChurnDoesNotDominateRankings() {
        let store = makeStore(named: "noisy-existing-deltas")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let newSongDate = date(year: 2026, month: 5, day: 6, hour: 8)
        let fillerSongs = (4...22).map { index in
            song(id: UInt64(index), title: "Stable Catalog Song \(index)", playCount: 1)
        }

        _ = store.record(
            songs: [
                song(id: 1, title: "Counter Churn Song", playCount: 100),
                song(id: 2, title: "Counter Drop Song", playCount: 500)
            ] + fillerSongs,
            at: baselineDate,
            reason: .manualRefresh
        )

        _ = store.record(
            songs: [
                song(id: 1, title: "Counter Churn Song", playCount: 300),
                song(id: 2, title: "Counter Drop Song", playCount: 324),
                song(id: 3, title: "Sabrina New Song", playCount: 12, dateAdded: newSongDate)
            ] + fillerSongs,
            at: latestDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 36)
        XCTAssertEqual(recap.topSongs.first?.title, "Sabrina New Song")
        XCTAssertEqual(recap.topSongs.first?.playDelta, 12)
        XCTAssertEqual(recap.topNewSongs.first?.title, "Sabrina New Song")
        XCTAssertTrue(recap.biggestGainers.isEmpty)
    }

    func testDeletedAndReaddedSongCombinesCounterEpochsWithoutFreezingSyncedRecap() {
        let store = makeStore(named: "readded-new-id")
        let baselineDate = date(year: 2026, month: 6, day: 29)
        let beforeDeletion = date(year: 2026, month: 7, day: 22, hour: 10)
        let deleted = date(year: 2026, month: 7, day: 22, hour: 11)
        let readded = date(year: 2026, month: 7, day: 22, hour: 13)
        let latest = date(year: 2026, month: 7, day: 30)
        let originalDateAdded = date(year: 2026, month: 5, day: 29)

        _ = store.record(
            songs: [
                song(
                    id: 1,
                    title: "Counter Epoch Song",
                    albumTitle: "Original Album",
                    playCount: 269,
                    dateAdded: originalDateAdded,
                    playbackStoreID: "catalog-song"
                ),
                song(id: 99, title: "Stable Filler", playCount: 100)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [
                song(
                    id: 1,
                    title: "Counter Epoch Song",
                    albumTitle: "Original Album",
                    playCount: 313,
                    dateAdded: originalDateAdded,
                    playbackStoreID: "catalog-song"
                ),
                song(id: 99, title: "Stable Filler", playCount: 100)
            ],
            at: beforeDeletion,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 99, title: "Stable Filler", playCount: 100)],
            at: deleted,
            reason: .libraryChanged
        )
        _ = store.record(
            songs: [
                song(
                    id: 2,
                    title: "Counter Epoch Song",
                    albumTitle: "Deluxe Album",
                    playCount: 10,
                    dateAdded: deleted,
                    playbackStoreID: "catalog-song"
                ),
                song(id: 99, title: "Stable Filler", playCount: 100)
            ],
            at: readded,
            reason: .appLaunch
        )
        let recap = store.record(
            songs: [
                song(
                    id: 2,
                    title: "Counter Epoch Song",
                    albumTitle: "Deluxe Album",
                    playCount: 71,
                    dateAdded: deleted,
                    playbackStoreID: "catalog-song"
                ),
                song(id: 99, title: "Stable Filler", playCount: 100)
            ],
            at: latest,
            reason: .appLaunch
        )

        XCTAssertEqual(recap.totalPlayDelta, 115)
        XCTAssertEqual(recap.topSongs.count, 1)
        XCTAssertEqual(recap.topSongs.first?.id, 2)
        XCTAssertEqual(recap.topSongs.first?.albumTitle, "Deluxe Album")
        XCTAssertEqual(recap.topSongs.first?.playDelta, 115)
        XCTAssertTrue(recap.topNewSongs.isEmpty)
        XCTAssertEqual(recap.generatedAt, latest)
    }

    func testSamePersistentIDCounterResetStartsANewEpochWhenDateAddedAdvances() {
        let store = makeStore(named: "readded-same-id")
        let baselineDate = date(year: 2026, month: 6, day: 29)
        let beforeReset = date(year: 2026, month: 7, day: 22, hour: 10)
        let resetDate = date(year: 2026, month: 7, day: 22, hour: 13)
        let latest = date(year: 2026, month: 7, day: 30)
        let originalDateAdded = date(year: 2026, month: 5, day: 29)

        _ = store.record(
            songs: [song(id: 1, title: "Same ID Reset", playCount: 269, dateAdded: originalDateAdded)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [song(id: 1, title: "Same ID Reset", playCount: 313, dateAdded: originalDateAdded)],
            at: beforeReset,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Same ID Reset", playCount: 10, dateAdded: resetDate)],
            at: resetDate,
            reason: .libraryChanged
        )
        let recap = store.record(
            songs: [song(id: 1, title: "Same ID Reset", playCount: 71, dateAdded: resetDate)],
            at: latest,
            reason: .appLaunch
        )

        XCTAssertEqual(recap.totalPlayDelta, 115)
        XCTAssertEqual(recap.topSongs.first?.playDelta, 115)
        XCTAssertTrue(recap.topNewSongs.isEmpty)
    }

    func testDeletingSongPreservesPlaysAlreadyObservedThisMonth() {
        let store = makeStore(named: "deleted-preserves-month")
        let baselineDate = date(year: 2026, month: 6, day: 29)
        let beforeDeletion = date(year: 2026, month: 7, day: 22)
        let afterDeletion = date(year: 2026, month: 7, day: 23)

        _ = store.record(
            songs: [
                song(id: 1, title: "Deleted Song", playCount: 269),
                song(id: 99, title: "Stable Filler", playCount: 100)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [
                song(id: 1, title: "Deleted Song", playCount: 313),
                song(id: 99, title: "Stable Filler", playCount: 100)
            ],
            at: beforeDeletion,
            reason: .appLaunch
        )
        let recap = store.record(
            songs: [song(id: 99, title: "Stable Filler", playCount: 100)],
            at: afterDeletion,
            reason: .libraryChanged
        )

        XCTAssertEqual(recap.totalPlayDelta, 44)
        XCTAssertEqual(recap.topSongs.first?.title, "Deleted Song")
        XCTAssertEqual(recap.topSongs.first?.playDelta, 44)
    }

    func testYearlyRecapCombinesRecordingAcrossPersistentIDReplacement() {
        let store = makeStore(named: "yearly-readded")
        let mayBaseline = date(year: 2026, month: 5, day: 31)
        let juneLatest = date(year: 2026, month: 6, day: 30)
        let julyBaseline = date(year: 2026, month: 7, day: 1)
        let julyDeletion = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 30)
        let originalDateAdded = date(year: 2026, month: 5, day: 29)

        _ = store.record(
            songs: [song(id: 1, title: "Yearly Epoch Song", playCount: 269, dateAdded: originalDateAdded)],
            at: mayBaseline,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [song(id: 1, title: "Yearly Epoch Song", playCount: 313, dateAdded: originalDateAdded)],
            at: juneLatest,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Yearly Epoch Song", playCount: 313, dateAdded: originalDateAdded)],
            at: julyBaseline,
            reason: .appLaunch
        )
        _ = store.record(songs: [], at: julyDeletion, reason: .libraryChanged)
        let julyRecap = store.record(
            songs: [
                song(
                    id: 2,
                    title: "Yearly Epoch Song",
                    playCount: 71,
                    dateAdded: julyDeletion,
                    albumPersistentID: 100,
                    artistPersistentID: 200
                )
            ],
            at: julyLatest,
            reason: .appLaunch
        )

        XCTAssertEqual(julyRecap.totalPlayDelta, 71)
        let yearly = store.syncedYearlyRecap(for: 2026)
        XCTAssertEqual(
            yearly?.totalPlayDelta,
            115,
            store.privacySafeDiagnostics(at: julyLatest)
        )
        XCTAssertEqual(yearly?.playedSongCount, 1)
        XCTAssertEqual(yearly?.topSongs.count, 1)
        XCTAssertEqual(yearly?.topSongs.first?.id, 2)
        XCTAssertEqual(yearly?.topSongs.first?.playDelta, 115)
        XCTAssertEqual(yearly?.topArtists.count, 1)
        XCTAssertEqual(yearly?.topArtists.first?.id, "200")
        XCTAssertEqual(yearly?.topArtists.first?.playDelta, 115)
        XCTAssertEqual(yearly?.topAlbums.count, 1)
        XCTAssertEqual(yearly?.topAlbums.first?.id, "100")
        XCTAssertEqual(yearly?.topAlbums.first?.playDelta, 115)
    }

    func testReaddAcrossMonthBoundaryKeepsYearlyIdentityWithoutBecomingTopNew() {
        let store = makeStore(named: "yearly-readded-across-month")
        let mayBaseline = date(year: 2026, month: 5, day: 31)
        let juneHighWater = date(year: 2026, month: 6, day: 20)
        let juneDeletion = date(year: 2026, month: 6, day: 30)
        let julyReadd = date(year: 2026, month: 7, day: 2)
        let originalDateAdded = date(year: 2026, month: 5, day: 29)

        _ = store.record(
            songs: [song(id: 1, title: "Boundary Epoch Song", playCount: 269, dateAdded: originalDateAdded)],
            at: mayBaseline,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [song(id: 1, title: "Boundary Epoch Song", playCount: 313, dateAdded: originalDateAdded)],
            at: juneHighWater,
            reason: .appLaunch
        )
        _ = store.record(songs: [], at: juneDeletion, reason: .libraryChanged)
        let july = store.record(
            songs: [song(id: 2, title: "Boundary Epoch Song", playCount: 71, dateAdded: julyReadd)],
            at: julyReadd,
            reason: .appLaunch
        )

        XCTAssertEqual(july.totalPlayDelta, 71)
        XCTAssertEqual(july.topSongs.first?.id, 2)
        XCTAssertTrue(july.topNewSongs.isEmpty)

        let yearly = store.syncedYearlyRecap(for: 2026)
        XCTAssertEqual(yearly?.totalPlayDelta, 115)
        XCTAssertEqual(yearly?.topSongs.count, 1)
        XCTAssertEqual(yearly?.topSongs.first?.id, 2)
        XCTAssertEqual(yearly?.topSongs.first?.playDelta, 115)
    }

    func testBatchRecapsReuseOneSnapshotLoadPath() {
        let store = makeStore(named: "batch")
        let aprilBaseline = date(year: 2026, month: 4, day: 1)
        let aprilLatest = date(year: 2026, month: 4, day: 15)
        let mayLatest = date(year: 2026, month: 5, day: 3)

        _ = store.record(
            songs: [song(id: 1, title: "April Song", playCount: 3)],
            at: aprilBaseline,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [song(id: 1, title: "April Song", playCount: 8)],
            at: aprilLatest,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "April Song", playCount: 10)],
            at: mayLatest,
            reason: .foreground
        )

        let recaps = store.recaps(forMonthsContaining: [aprilLatest, mayLatest])
        XCTAssertEqual(recaps.map(\.totalPlayDelta), [5, 2])
    }

    func testRecapArtistGroupsUseNameFallbackWhenPersistentIDIsMissing() {
        let store = makeStore(named: "zero-artist-groups")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)

        _ = store.record(
            songs: [
                song(id: 1, title: "First Song", artist: "First Artist", playCount: 10, artistPersistentID: 0),
                song(id: 2, title: "Second Song", artist: "Second Artist", playCount: 10, artistPersistentID: 0)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [
                song(id: 1, title: "First Song", artist: "First Artist", playCount: 13, artistPersistentID: 0),
                song(id: 2, title: "Second Song", artist: "Second Artist", playCount: 15, artistPersistentID: 0)
            ],
            at: latestDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: latestDate)

        XCTAssertEqual(recap.topArtists.map(\.title), ["Second Artist", "First Artist"])
        XCTAssertEqual(recap.topArtists.map(\.playDelta), [5, 3])
    }

    func testRecapAlbumGroupsUseTitleArtistFallbackWhenPersistentIDIsMissing() {
        let store = makeStore(named: "zero-album-groups")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)

        _ = store.record(
            songs: [
                song(id: 1, title: "First Song", artist: "First Artist", albumTitle: "First Album", playCount: 10, albumPersistentID: 0),
                song(id: 2, title: "Second Song", artist: "Second Artist", albumTitle: "Second Album", playCount: 10, albumPersistentID: 0)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [
                song(id: 1, title: "First Song", artist: "First Artist", albumTitle: "First Album", playCount: 13, albumPersistentID: 0),
                song(id: 2, title: "Second Song", artist: "Second Artist", albumTitle: "Second Album", playCount: 15, albumPersistentID: 0)
            ],
            at: latestDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: latestDate)

        XCTAssertEqual(recap.topAlbums.map(\.title), ["Second Album", "First Album"])
        XCTAssertEqual(recap.topAlbums.map(\.playDelta), [5, 3])
    }

    func testRecapAlbumGroupsUseAlbumArtistForCompilationSubtitles() {
        let store = makeStore(named: "compilation-album-groups")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)

        _ = store.record(
            songs: [
                song(id: 1, title: "First Song", artist: "Track Artist A", albumArtist: "Various Artists", albumTitle: "Compilation", playCount: 10, albumPersistentID: 42),
                song(id: 2, title: "Second Song", artist: "Track Artist B", albumArtist: "Various Artists", albumTitle: "Compilation", playCount: 10, albumPersistentID: 42)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [
                song(id: 1, title: "First Song", artist: "Track Artist A", albumArtist: "Various Artists", albumTitle: "Compilation", playCount: 13, albumPersistentID: 42),
                song(id: 2, title: "Second Song", artist: "Track Artist B", albumArtist: "Various Artists", albumTitle: "Compilation", playCount: 15, albumPersistentID: 42)
            ],
            at: latestDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: latestDate)

        XCTAssertEqual(recap.topAlbums.first?.title, "Compilation")
        XCTAssertEqual(recap.topAlbums.first?.subtitle, "Various Artists")
        XCTAssertEqual(recap.topAlbums.first?.playDelta, 8)
    }

    func testBiggestGainersIncludesAlbumsAndArtistsUsingGroupRankMovement() {
        let store = makeStore(named: "group-gainers")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)
        let incrementalDate = date(year: 2026, month: 5, day: 9)
        let baseline = [
            song(id: 1, title: "A", artist: "Artist A", albumTitle: "Album A", playCount: 100, albumPersistentID: 101, artistPersistentID: 201),
            song(id: 2, title: "B", artist: "Artist B", albumTitle: "Album B", playCount: 80, albumPersistentID: 102, artistPersistentID: 202),
            song(id: 3, title: "C", artist: "Artist C", albumTitle: "Album C", playCount: 60, albumPersistentID: 103, artistPersistentID: 203)
        ]
        let latest = [baseline[0], baseline[1],
                      song(id: 3, title: "C", artist: "Artist C", albumTitle: "Album C", playCount: 110, albumPersistentID: 103, artistPersistentID: 203)]

        _ = store.record(songs: baseline, at: baselineDate, reason: .manualRefresh)
        _ = store.record(songs: latest, at: latestDate, reason: .foreground)
        let recap = store.record(
            songs: [baseline[0], baseline[1],
                    song(id: 3, title: "C", artist: "Artist C", albumTitle: "Album C", playCount: 120, albumPersistentID: 103, artistPersistentID: 203)],
            at: incrementalDate,
            reason: .foreground
        )

        XCTAssertEqual(recap.biggestAlbumGainers.first?.title, "Album C")
        XCTAssertEqual(recap.biggestAlbumGainers.first?.rankChange, 2)
        XCTAssertEqual(recap.biggestAlbumGainers.first?.playDelta, 60)
        XCTAssertEqual(recap.biggestArtistGainers.first?.title, "Artist C")
        XCTAssertEqual(recap.biggestArtistGainers.first?.rankChange, 2)
        XCTAssertEqual(recap.biggestArtistGainers.first?.playDelta, 60)

        let syncedStore = makeStore(named: "group-gainers-synced")
        XCTAssertTrue(syncedStore.mergeSyncPayloads(store.localSyncPayloads(), now: incrementalDate))
        let syncedRecap = syncedStore.recap(forMonthContaining: incrementalDate)
        XCTAssertEqual(syncedRecap.biggestAlbumGainers, recap.biggestAlbumGainers)
        XCTAssertEqual(syncedRecap.biggestArtistGainers, recap.biggestArtistGainers)
    }

    func testCompactRecapSummarySurvivesAColdStoreInstance() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountRecapSummary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-source"
        )
        _ = source.record(
            songs: [song(id: 1, title: "Summary Song", playCount: 10)],
            at: baselineDate,
            reason: .appLaunch
        )
        _ = source.record(
            songs: [song(id: 1, title: "Summary Song", playCount: 16)],
            at: latestDate,
            reason: .foreground
        )

        let coldStore = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "summary-reader"
        )
        let cached = try XCTUnwrap(coldStore.cachedRecapSummaries().last)

        XCTAssertEqual(cached.monthStart, calendar.startOfMonth(containing: baselineDate))
        XCTAssertEqual(cached.topSongs.first?.title, "Summary Song")
        XCTAssertEqual(cached.topSongs.first?.playDelta, 6)
    }

    func testArchivedRecapsStillProduceManifestArchiveWhenAllSnapshotsAgeOut() {
        let store = makeStore(named: "archive-only-after-retention")
        let baseline = date(year: 2024, month: 1, day: 1)
        let latest = date(year: 2024, month: 1, day: 3)
        _ = store.record(
            songs: [song(id: 1, title: "Archived", playCount: 10)],
            at: baseline,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "Archived", playCount: 14)],
            at: latest,
            reason: .foreground
        )

        let payloads = store.syncPayloads()

        XCTAssertEqual(payloads.count, 1)
        XCTAssertTrue(payloads[0].isManifestArchiveOnly)
        XCTAssertNotNil(payloads[0].encodedRecaps)
        XCTAssertNotNil(payloads[0].encodedYearlyRecaps)
    }

    func testDeltaLedgerStorageScalesWithChangesInsteadOfFullLibraryCopies() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountDeltaLedger-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "delta-ledger"
        )
        let baselineDate = date(year: 2026, month: 7, day: 1)
        var currentSongs = (1...1_000).map {
            song(id: UInt64($0), title: "Library Song \($0)", playCount: 10)
        }
        _ = store.record(songs: currentSongs, at: baselineDate, reason: .appLaunch)

        for update in 1...40 {
            currentSongs[update - 1] = song(
                id: UInt64(update),
                title: "Library Song \(update)",
                playCount: 10 + update
            )
            _ = store.record(
                songs: currentSongs,
                at: baselineDate.addingTimeInterval(TimeInterval(update * 3_600)),
                reason: .manualRefresh
            )
        }

        let ledgerURL = directory.appendingPathComponent("recap-ledger.sqlite")
        let legacyURL = directory.appendingPathComponent("monthly-recap-snapshots.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ledgerURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

        let ledgerBytes = [ledgerURL.path, ledgerURL.path + "-wal", ledgerURL.path + "-shm"]
            .compactMap { try? FileManager.default.attributesOfItem(atPath: $0)[.size] as? NSNumber }
            .reduce(Int64(0)) { $0 + $1.int64Value }
        XCTAssertLessThan(ledgerBytes, 3_000_000)

        let coldStore = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: "delta-ledger"
        )
        let recap = coldStore.recap(forMonthContaining: baselineDate)
        XCTAssertEqual(recap.totalPlayDelta, (1...40).reduce(0, +))
        XCTAssertEqual(recap.topSongs.first?.playDelta, 40)
    }

    func testDeltaLedgerPreservesSnapshotIdentityAcrossColdReload() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLedgerOrder-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "ordered-ledger"
        )
        let capturedAt = date(year: 2026, month: 7, day: 15)
        _ = source.record(
            songs: [
                song(id: 90, title: "First Query Result", playCount: 40),
                song(id: 2, title: "Second Query Result", playCount: 10),
                song(id: 41, title: "Third Query Result", playCount: 20)
            ],
            at: capturedAt,
            reason: .manualRefresh
        )
        let expectedIDs = source.localSyncPayloads().map(\.id)

        let coldStore = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "ordered-ledger"
        )
        XCTAssertEqual(coldStore.localSyncPayloads().map(\.id), expectedIDs)
    }

    func testLegacyArchiveMigratesOnlyAfterMonthlyAndYearlyParity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let source = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "migration-device"
        )
        let mayBaseline = date(year: 2026, month: 5, day: 1)
        let mayLatest = date(year: 2026, month: 5, day: 20)
        let julyBaseline = date(year: 2026, month: 7, day: 1)
        let julyDeletion = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 20)

        _ = source.record(
            songs: [song(id: 1, title: "Migrated Epoch", playCount: 100)],
            at: mayBaseline,
            reason: .appLaunch
        )
        _ = source.record(
            songs: [song(id: 1, title: "Migrated Epoch", playCount: 125)],
            at: mayLatest,
            reason: .manualRefresh
        )
        _ = source.record(
            songs: [song(id: 1, title: "Migrated Epoch", playCount: 125)],
            at: julyBaseline,
            reason: .appLaunch
        )
        _ = source.record(songs: [], at: julyDeletion, reason: .libraryChanged)
        _ = source.record(
            songs: [song(id: 2, title: "Migrated Epoch", playCount: 30, dateAdded: julyDeletion)],
            at: julyLatest,
            reason: .appLaunch
        )

        let expectedMay = source.recap(forMonthContaining: mayLatest)
        let expectedJuly = source.recap(forMonthContaining: julyLatest)
        let expectedYear = try XCTUnwrap(source.syncedYearlyRecap(for: 2026))
        try source.debugCreateLegacyArchiveForMigration()

        let legacyURL = directory.appendingPathComponent("monthly-recap-snapshots.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

        let migrated = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "migration-device"
        )
        migrated.prepareStorage()
        XCTAssertEqual(migrated.recap(forMonthContaining: mayLatest).totalPlayDelta, expectedMay.totalPlayDelta)
        XCTAssertEqual(migrated.recap(forMonthContaining: julyLatest).totalPlayDelta, expectedJuly.totalPlayDelta)
        XCTAssertEqual(migrated.syncedYearlyRecap(for: 2026)?.totalPlayDelta, expectedYear.totalPlayDelta)
        XCTAssertEqual(migrated.syncedYearlyRecap(for: 2026)?.topSongs.first?.playDelta, expectedYear.topSongs.first?.playDelta)
        XCTAssertEqual(migrated.availableMonthStarts(through: julyLatest).count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recap-ledger.sqlite").path))

        let postMigrationDate = date(year: 2026, month: 7, day: 21)
        let advanced = migrated.record(
            songs: [song(id: 2, title: "Migrated Epoch", playCount: 35, dateAdded: julyDeletion)],
            at: postMigrationDate,
            reason: .foreground
        )
        XCTAssertEqual(advanced.totalPlayDelta, expectedJuly.totalPlayDelta + 5)
        XCTAssertEqual(
            migrated.syncedYearlyRecap(for: 2026)?.totalPlayDelta,
            expectedYear.totalPlayDelta + 5
        )
    }

    func testMissedMonthStartsFreshMonthlyBaselineButPreservesSameYearActivity() throws {
        let store = makeStore(named: "same-year-gap")
        let mayEnd = date(year: 2026, month: 5, day: 31)
        let julyReturn = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 15)

        _ = store.record(
            songs: [song(id: 1, title: "Gap Song", playCount: 100)],
            at: mayEnd,
            reason: .foreground
        )
        let returnRecap = store.record(
            songs: [song(id: 1, title: "Gap Song", playCount: 130)],
            at: julyReturn,
            reason: .appLaunch
        )

        XCTAssertEqual(returnRecap.totalPlayDelta, 0)
        XCTAssertEqual(returnRecap.snapshotCount, 1)
        XCTAssertEqual(returnRecap.trackingStart, julyReturn)

        let june = store.recap(forMonthContaining: date(year: 2026, month: 6, day: 15))
        XCTAssertEqual(june.totalPlayDelta, 0)
        XCTAssertEqual(june.snapshotCount, 0)

        let july = store.record(
            songs: [song(id: 1, title: "Gap Song", playCount: 135)],
            at: julyLatest,
            reason: .foreground
        )
        XCTAssertEqual(july.totalPlayDelta, 5)
        XCTAssertEqual(july.topSongs.first?.playDelta, 5)

        let yearly = try XCTUnwrap(store.syncedYearlyRecap(for: 2026))
        XCTAssertEqual(yearly.totalPlayDelta, 35)
        XCTAssertEqual(yearly.topSongs.first?.playDelta, 35)
        XCTAssertEqual(yearly.unattributedPlayDelta, 30)

        let payloads = store.localSyncPayloads()
        XCTAssertEqual(payloads.filter { $0.encodedUnattributedIntervals != nil }.count, min(2, payloads.count))
        let cloudRoundTripPayloads = payloads.map {
            RecapSnapshotSyncPayload(
                id: $0.id,
                capturedAt: $0.capturedAt,
                counterSignature: $0.counterSignature,
                encodedSnapshot: $0.encodedSnapshot,
                encodedRecaps: $0.encodedRecaps,
                encodedYearlyRecaps: $0.encodedYearlyRecaps
            )
        }
        let synced = makeStore(named: "same-year-gap-synced")
        XCTAssertTrue(synced.mergeSyncPayloads(cloudRoundTripPayloads, now: julyLatest))
        XCTAssertEqual(synced.recap(forMonthContaining: julyLatest).totalPlayDelta, 5)
        XCTAssertEqual(synced.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 35)
        XCTAssertEqual(synced.syncedYearlyRecap(for: 2026)?.unattributedPlayDelta, 30)
    }

    func testCrossYearGapIsNotGuessedIntoEitherYear() throws {
        let store = makeStore(named: "cross-year-gap")
        let novemberEnd = date(year: 2026, month: 11, day: 30)
        let februaryReturn = date(year: 2027, month: 2, day: 10)
        let februaryLatest = date(year: 2027, month: 2, day: 15)

        _ = store.record(
            songs: [song(id: 1, title: "Year Boundary", playCount: 100)],
            at: novemberEnd,
            reason: .foreground
        )
        let returnRecap = store.record(
            songs: [song(id: 1, title: "Year Boundary", playCount: 130)],
            at: februaryReturn,
            reason: .appLaunch
        )
        let february = store.record(
            songs: [song(id: 1, title: "Year Boundary", playCount: 135)],
            at: februaryLatest,
            reason: .foreground
        )

        XCTAssertEqual(returnRecap.totalPlayDelta, 0)
        XCTAssertEqual(february.totalPlayDelta, 5)
        let yearly = try XCTUnwrap(store.syncedYearlyRecap(for: 2027))
        XCTAssertEqual(yearly.totalPlayDelta, 5)
        XCTAssertEqual(yearly.unattributedPlayDelta, 0)
    }

    func testUnattributedIntervalSurvivesColdLedgerReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountGapReload-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let mayEnd = date(year: 2026, month: 5, day: 31)
        let julyReturn = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 15)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "gap-reload"
        )

        _ = store.record(songs: [song(id: 1, title: "Reload Gap", playCount: 100)], at: mayEnd, reason: .foreground)
        _ = store.record(songs: [song(id: 1, title: "Reload Gap", playCount: 130)], at: julyReturn, reason: .appLaunch)
        _ = store.record(songs: [song(id: 1, title: "Reload Gap", playCount: 135)], at: julyLatest, reason: .foreground)

        let coldStore = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "gap-reload"
        )
        let yearly = try XCTUnwrap(coldStore.syncedYearlyRecap(for: 2026))
        XCTAssertEqual(coldStore.recap(forMonthContaining: julyLatest).totalPlayDelta, 5)
        XCTAssertEqual(yearly.totalPlayDelta, 35)
        XCTAssertEqual(yearly.unattributedPlayDelta, 30)
    }

    func testExistingInflatedGapLedgerIsMigratedOnceOnColdLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountGapPolicyMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar(identifier: .gregorian)
        let mayEnd = date(year: 2026, month: 5, day: 31)
        let julyReturn = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 15)
        let store = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "gap-policy-migration"
        )

        _ = store.record(songs: [song(id: 1, title: "Migrated Gap", playCount: 100)], at: mayEnd, reason: .foreground)
        _ = store.record(songs: [song(id: 1, title: "Migrated Gap", playCount: 130)], at: julyReturn, reason: .appLaunch)
        _ = store.record(songs: [song(id: 1, title: "Migrated Gap", playCount: 135)], at: julyLatest, reason: .foreground)

        let legacyRankedSong = MonthlyRecap.RankedSong(
            id: 1,
            title: "Migrated Gap",
            artist: "Artist",
            albumTitle: "Album",
            playDelta: 35,
            skipDelta: 0,
            listeningDuration: 35 * 180,
            artwork: nil
        )
        store.debugInstallPreGapPolicyRecap(
            MonthlyRecap(
                monthStart: calendar.startOfMonth(containing: julyLatest),
                generatedAt: julyLatest,
                lastCaptureReason: .foreground,
                trackingStart: mayEnd,
                snapshotCount: 2,
                totalPlayDelta: 35,
                totalSkipDelta: 0,
                totalListeningDuration: 35 * 180,
                playedSongCount: 1,
                newSongCount: 0,
                topSongs: [legacyRankedSong],
                topArtists: [],
                topAlbums: [],
                biggestGainers: [],
                topNewSongs: []
            )
        )

        let migrated = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "gap-policy-migration"
        )
        XCTAssertEqual(migrated.recap(forMonthContaining: julyLatest).totalPlayDelta, 5)
        XCTAssertEqual(migrated.syncedYearlyRecap(for: 2026)?.totalPlayDelta, 35)
        XCTAssertEqual(migrated.syncedYearlyRecap(for: 2026)?.unattributedPlayDelta, 30)

        let secondColdLoad = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "gap-policy-migration"
        )
        XCTAssertEqual(secondColdLoad.recap(forMonthContaining: julyLatest).totalPlayDelta, 5)
        XCTAssertEqual(secondColdLoad.syncedYearlyRecap(for: 2026)?.unattributedPlayDelta, 30)
    }

    func testAdjacentMonthBoundaryKeepsExistingContinuousTrackingBehavior() {
        let store = makeStore(named: "adjacent-month")
        let juneEnd = date(year: 2026, month: 6, day: 30)
        let julyReturn = date(year: 2026, month: 7, day: 2)

        _ = store.record(
            songs: [song(id: 1, title: "Continuous Song", playCount: 100)],
            at: juneEnd,
            reason: .foreground
        )
        let july = store.record(
            songs: [song(id: 1, title: "Continuous Song", playCount: 104)],
            at: julyReturn,
            reason: .foreground
        )

        XCTAssertEqual(july.totalPlayDelta, 4)
        XCTAssertEqual(july.topSongs.first?.playDelta, 4)
        XCTAssertEqual(july.unattributedPlayDelta, 0)
    }

    func testDetailedSyncedCoverageSupersedesOverlappingGapEvidence() throws {
        let gapStore = makeStore(named: "gap-device")
        let detailedStore = makeStore(named: "detailed-device")
        let target = makeStore(named: "gap-reconciliation-target")
        let mayEnd = date(year: 2026, month: 5, day: 31)
        let juneEnd = date(year: 2026, month: 6, day: 30)
        let julyStart = date(year: 2026, month: 7, day: 1)
        let julyReturn = date(year: 2026, month: 7, day: 10)
        let julyLatest = date(year: 2026, month: 7, day: 15)

        _ = gapStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 100)], at: mayEnd, reason: .foreground)
        _ = gapStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 130)], at: julyReturn, reason: .appLaunch)
        _ = gapStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 135)], at: julyLatest, reason: .foreground)

        _ = detailedStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 100)], at: mayEnd, reason: .foreground)
        _ = detailedStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 115)], at: juneEnd, reason: .foreground)
        _ = detailedStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 115)], at: julyStart, reason: .foreground)
        _ = detailedStore.record(songs: [song(id: 1, title: "Covered Gap", playCount: 135)], at: julyLatest, reason: .foreground)

        XCTAssertTrue(target.mergeSyncPayloads(gapStore.localSyncPayloads(), now: julyLatest))
        XCTAssertTrue(target.mergeSyncPayloads(detailedStore.localSyncPayloads(), now: julyLatest))

        let yearly = try XCTUnwrap(target.syncedYearlyRecap(for: 2026))
        XCTAssertEqual(yearly.totalPlayDelta, 35)
        XCTAssertEqual(yearly.topSongs.first?.playDelta, 35)
        XCTAssertEqual(yearly.unattributedPlayDelta, 0)
        let diagnostics = target.recapDiagnosticsReport(at: julyLatest)
        XCTAssertEqual(diagnostics.unattributedIntervalCount, 0)
        XCTAssertEqual(diagnostics.unattributedPlayDelta, 0)
    }

    private func makeStore(named name: String) -> MonthlyRecapSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        return MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: name
        )
    }

    private var playCountDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct LegacySyncedMonthlyRecap: Decodable {
        struct RankedSong: Decodable {
            let title: String
        }

        let totalPlayDelta: Int
        let topSongs: [RankedSong]
    }

    private func song(
        id: UInt64,
        title: String,
        artist: String = "Artist",
        albumArtist: String? = nil,
        albumTitle: String = "Album",
        playCount: Int,
        dateAdded: Date? = nil,
        albumPersistentID: UInt64 = 10,
        artistPersistentID: UInt64 = 20,
        playbackStoreID: String = ""
    ) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            albumArtist: albumArtist ?? artist,
            playCount: playCount,
            skipCount: 0,
            totalPlayDuration: TimeInterval(playCount * 180),
            playbackDuration: 180,
            lastPlayedDate: nil,
            dateAdded: dateAdded,
            artwork: nil,
            albumPersistentID: albumPersistentID,
            artistPersistentID: artistPersistentID,
            trackNumber: 1,
            playbackStoreID: playbackStoreID
        )
    }

    private func recapFixtureSongs(climberPlayCount: Int, otherPlayCounts: [Int]) -> [TopSong] {
        var songs = otherPlayCounts.enumerated().map { index, playCount in
            song(id: UInt64(index + 1), title: "Catalog Song \(index + 1)", playCount: playCount)
        }
        songs.append(song(id: 100, title: "Climber", playCount: climberPlayCount))
        return songs
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}

private final class SnapshotCommitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingAllowedChecks: Int

    init(allowedChecks: Int) {
        remainingAllowedChecks = allowedChecks
    }

    func shouldCommit() -> Bool {
        lock.withLock {
            guard remainingAllowedChecks > 0 else { return false }
            remainingAllowedChecks -= 1
            return true
        }
    }
}

private final class PersistenceWriteGate {
    var isAllowed = true
}
