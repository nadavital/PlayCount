import XCTest
import MediaPlayer
@testable import PlayCount

final class StartupReliabilityTests: XCTestCase {
    @MainActor
    func testCachedAndLiveLibraryPublishWhileRecapStoreIsBlocked() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = StartupGate()
        let storeBlocked = expectation(description: "Recap storage occupied")
        let storeReleased = expectation(description: "Recap storage released")
        let store = MonthlyRecapSnapshotStore(directoryURL: directory, persistenceReadAllowed: {
            storeBlocked.fulfill()
            gate.wait()
            return true
        })
        DispatchQueue.global().async(execute: DispatchWorkItem {
            store.prepareStorage()
            storeReleased.fulfill()
        })
        defer { gate.open() }
        await fulfillment(of: [storeBlocked], timeout: 2)

        let readGate = StartupGate()
        defer { readGate.open() }
        let cachedSong = song(id: 1, plays: 10)
        let liveSong = song(id: 1, plays: 11)
        let cache = LibraryPresentationCache(directoryURL: directory)
        cache.save(songs: [cachedSong])
        let manager = makeManager(directory: directory, store: store, cache: cache, readSongs: {
            readGate.wait()
            return [liveSong]
        })
        manager.refreshForRecapSequence(reason: .appLaunch)
        await assertEventually { manager.isShowingCachedLibrary && manager.topSongs.first?.playCount == 10 }
        XCTAssertTrue(manager.hasLoadedInitialSnapshot)
        let presentationReadStart = Date()
        _ = manager.recap(forMonthContaining: Date().addingTimeInterval(-90 * 86_400))
        _ = manager.recaps(forMonthsContaining: [Date()])
        _ = manager.yearlyRecap(for: 2025)
        _ = manager.yearToDateRecap(through: Date())
        _ = manager.yearlyMonthlyHighlights(for: 2025)
        XCTAssertLessThan(Date().timeIntervalSince(presentationReadStart), 0.1,
                          "View getters cannot wait on the occupied recap queue")
        readGate.open()
        await assertEventually { manager.topSongs.first?.playCount == 11 && !manager.isLoading }
        XCTAssertTrue(manager.isPreparingInsights)
        gate.open()
        await fulfillment(of: [storeReleased], timeout: 2)
        await assertEventually { !manager.isPreparingInsights }
    }

    @MainActor
    func testFreshLibraryAndDiskCacheAreUsableBeforeMilestonesFinish() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = MediaMilestoneLedger(fileURL: directory.appendingPathComponent("medals.sqlite"))
        let gate = StartupGate()
        defer { gate.open() }
        let blocked = expectation(description: "Milestone database occupied")
        let released = expectation(description: "Milestone database released")
        DispatchQueue.global().async {
            ledger.debugWithExclusiveDatabaseAccess {
                blocked.fulfill()
                gate.wait()
            }
            released.fulfill()
        }
        await fulfillment(of: [blocked], timeout: 2)
        let source = song(id: 2, plays: 20)
        let cache = LibraryPresentationCache(directoryURL: directory)
        let manager = makeManager(directory: directory, cache: cache, ledger: ledger, readSongs: { [source] })
        manager.refreshForRecapSequence(reason: .appLaunch)
        await assertEventually { manager.hasLoadedInitialSnapshot && !manager.isLoading }
        XCTAssertEqual(manager.topSongs.first?.id, 2)
        XCTAssertTrue(manager.isPreparingInsights)
        await assertEventually { cache.load()?.songs.first?.id == 2 }
        gate.open()
        await fulfillment(of: [released], timeout: 2)
        await assertEventually { !manager.isPreparingInsights }
    }

    @MainActor
    func testEmptyLiveQueryPreservesCachedLibraryAndDoesNotDeleteCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LibraryPresentationCache(directoryURL: directory)
        cache.save(songs: [song(id: 3, plays: 30)])
        let manager = makeManager(directory: directory, cache: cache, readSongs: { [] })
        manager.refreshForRecapSequence(reason: .appLaunch)
        await assertEventually { manager.hasLoadedInitialSnapshot && !manager.isLoading && !manager.isPreparingInsights }
        XCTAssertEqual(manager.topSongs.first?.playCount, 30)
        XCTAssertTrue(manager.isShowingCachedLibrary)
        XCTAssertEqual(cache.load()?.songs.first?.playCount, 30)
        XCTAssertEqual(manager.monthlyRecap.totalPlayDelta, 0, "Presentation cache must never become recap evidence")
    }

    @MainActor
    func testRevokedPermissionDropsLateReadAndCanRestartAfterReauthorization() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = StartupGate()
        defer { gate.open() }
        let started = expectation(description: "First media read started")
        let permission = StartupPermission()
        let source = song(id: 4, plays: 40)
        let reads = StartupReadCounter()
        let manager = makeManager(directory: directory, authorization: { permission.value }, readSongs: {
            if reads.increment() == 1 {
                started.fulfill()
                gate.wait()
            }
            return [source]
        })
        manager.refreshForRecapSequence(reason: .appLaunch)
        await fulfillment(of: [started], timeout: 2)
        permission.value = .denied
        XCTAssertFalse(manager.debugRevalidateAuthorizationStatus(.denied))
        gate.open()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(manager.librarySongs.isEmpty)
        XCTAssertFalse(manager.hasLoadedInitialSnapshot)
        permission.value = .authorized
        manager.refreshForRecapSequence(reason: .foreground)
        await assertEventually { manager.hasLoadedInitialSnapshot && !manager.isPreparingInsights }
        XCTAssertEqual(manager.topSongs.first?.id, 4)
        XCTAssertEqual(reads.value, 2)
    }

    @MainActor
    func testRepeatedLaunchCallbacksCoalesceAndDuplicateSongIDsDoNotInflateLibrary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = song(id: 5, plays: 50)
        let reads = StartupReadCounter()
        let manager = makeManager(directory: directory, readSongs: {
            _ = reads.increment()
            return [source, source]
        })
        for _ in 0..<10 {
            manager.refreshForRecapSequence(reason: .appLaunch)
            manager.refreshForRecapSequence(reason: .foreground)
        }
        await assertEventually { manager.hasLoadedInitialSnapshot && !manager.isPreparingInsights }
        XCTAssertEqual(reads.value, 1)
        XCTAssertEqual(manager.librarySummary.songCount, 1)
        XCTAssertEqual(manager.librarySummary.totalPlayCount, 50)
    }

    func testOversizedAndMalformedDisposableCachesFailOpenWithoutDeletingFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LibraryPresentationCache(directoryURL: directory, maximumCacheBytes: 256)
        let file = directory.appendingPathComponent("library-presentation.json")
        try Data(repeating: 32, count: 1_024).write(to: file)
        XCTAssertNil(cache.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try Data("{broken".utf8).write(to: file)
        XCTAssertNil(cache.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    func testLargeCachedLibraryPublishesWithoutWaitingForLiveScan() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = (1...20_000).map { song(id: UInt64($0), plays: $0 % 1_000 + 1) }
        let cache = LibraryPresentationCache(directoryURL: directory)
        cache.save(songs: source)
        let gate = StartupGate()
        defer { gate.open() }
        let readFinished = expectation(description: "Large library media read released")
        let manager = makeManager(directory: directory, cache: cache, readSongs: {
            gate.wait()
            readFinished.fulfill()
            return source
        })
        let start = Date()
        manager.refreshForRecapSequence(reason: .appLaunch)
        await assertEventually(timeout: 10) { manager.isShowingCachedLibrary }
        print("STARTUP_STRESS 20000 cached songs usable in \(Date().timeIntervalSince(start))s")
        XCTAssertEqual(manager.librarySongs.count, source.count)
        XCTAssertEqual(manager.librarySummary.totalPlayCount, source.reduce(0) { $0 + $1.playCount })
        // Cancel optional indexing/storage work before releasing the test's scan.
        XCTAssertFalse(manager.debugRevalidateAuthorizationStatus(.denied))
        gate.open()
        await fulfillment(of: [readFinished], timeout: 2)
    }

    func testInvalidCachedCountersCannotOverflowLibraryAggregation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LibraryPresentationCache(directoryURL: directory)
        cache.save(songs: [song(id: 1, plays: 10), song(id: 2, plays: 20)])
        let file = directory.appendingPathComponent("library-presentation.json")
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var songs = try XCTUnwrap(stored["songs"] as? [[String: Any]])
        songs[0]["playCount"] = NSNumber(value: Int.max)
        stored["songs"] = songs
        try JSONSerialization.data(withJSONObject: stored).write(to: file)
        XCTAssertNil(cache.load())
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    @MainActor
    private func assertEventually(timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line, _ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }

    private func makeManager(
        directory: URL,
        store: MonthlyRecapSnapshotStore? = nil,
        cache: LibraryPresentationCache? = nil,
        ledger: MediaMilestoneLedger? = nil,
        authorization: @escaping @Sendable () -> MPMediaLibraryAuthorizationStatus = { .authorized },
        readSongs: @escaping @Sendable () -> [TopSong]
    ) -> MediaLibraryManager {
        MediaLibraryManager(
            snapshotStore: store ?? MonthlyRecapSnapshotStore(directoryURL: directory),
            weeklyInsightStore: WeeklyRecapInsightStore(directoryURL: directory),
            milestoneLedger: ledger ?? MediaMilestoneLedger(fileURL: directory.appendingPathComponent("medals.sqlite")),
            presentationCache: cache ?? LibraryPresentationCache(directoryURL: directory),
            recapCloudSyncService: nil,
            startsAutomatically: false,
            libraryAccess: .init(authorizationStatus: authorization, readSongs: readSongs)
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StartupTests-\(UUID())")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func song(id: UInt64, plays: Int) -> TopSong {
        TopSong(id: id, title: "Song \(id)", artist: "Artist \(id % 100)", albumTitle: "Album \(id % 1000)",
                albumArtist: "Artist \(id % 100)", playCount: plays, skipCount: 0,
                totalPlayDuration: Double(plays) * 180, playbackDuration: 180,
                lastPlayedDate: nil, dateAdded: nil, artwork: nil,
                albumPersistentID: id % 1_000 + 1, artistPersistentID: id % 100 + 1, trackNumber: 1)
    }
}

private final class StartupGate: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func wait() { _ = semaphore.wait(timeout: .now() + 15) }
    func open() { semaphore.signal() }
}

private final class StartupPermission: @unchecked Sendable {
    private let lock = NSLock()
    private var status = MPMediaLibraryAuthorizationStatus.authorized
    var value: MPMediaLibraryAuthorizationStatus {
        get { lock.withLock { status } }
        set { lock.withLock { status = newValue } }
    }
}

private final class StartupReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() -> Int { lock.withLock { count += 1; return count } }
}
