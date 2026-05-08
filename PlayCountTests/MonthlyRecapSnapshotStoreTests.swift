import XCTest
@testable import PlayCount

final class MonthlyRecapSnapshotStoreTests: XCTestCase {
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

    private func makeStore(named name: String) -> MonthlyRecapSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountTests-\(UUID().uuidString)-\(name)", isDirectory: true)
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
            albumPersistentID: 10,
            artistPersistentID: 20,
            trackNumber: 1
        )
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
