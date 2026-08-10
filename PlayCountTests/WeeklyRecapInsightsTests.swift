import XCTest
@testable import PlayCount

final class WeeklyRecapInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    func testWeeklyStoreUsesFirstObservationAsBaselineThenAccumulatesDeltas() throws {
        let directory = temporaryDirectory()
        let store = WeeklyRecapInsightStore(directoryURL: directory, calendar: calendar)
        let monday = date(2026, 8, 10, hour: 9)

        let baseline = store.record(recap: recap(month: 8, plays: 10, songPlays: 6), at: monday)
        XCTAssertEqual(baseline.current.totalPlayDelta, 0)
        XCTAssertEqual(baseline.current.snapshotCount, 1)

        let second = store.record(
            recap: recap(month: 8, plays: 14, songPlays: 10),
            at: date(2026, 8, 11, hour: 9)
        )
        XCTAssertEqual(second.current.totalPlayDelta, 4)
        XCTAssertEqual(second.current.topSong?.playDelta, 4)

        let third = store.record(
            recap: recap(month: 8, plays: 17, songPlays: 13),
            at: date(2026, 8, 12, hour: 9)
        )
        XCTAssertEqual(third.current.totalPlayDelta, 7)
        XCTAssertEqual(third.current.topSong?.playDelta, 7)
        XCTAssertEqual(third.current.snapshotCount, 3)
    }

    func testNewWeekDoesNotGuessAcrossBoundary() {
        let directory = temporaryDirectory()
        let store = WeeklyRecapInsightStore(directoryURL: directory, calendar: calendar)

        _ = store.record(
            recap: recap(month: 8, plays: 10, songPlays: 5),
            at: date(2026, 8, 10, hour: 9)
        )
        _ = store.record(
            recap: recap(month: 8, plays: 18, songPlays: 13),
            at: date(2026, 8, 14, hour: 9)
        )
        let newWeek = store.record(
            recap: recap(month: 8, plays: 24, songPlays: 19),
            at: date(2026, 8, 17, hour: 9)
        )

        XCTAssertEqual(newWeek.current.totalPlayDelta, 0)
        XCTAssertEqual(newWeek.current.snapshotCount, 1)
        XCTAssertEqual(newWeek.previous?.totalPlayDelta, 8)

        let updated = store.record(
            recap: recap(month: 8, plays: 28, songPlays: 23),
            at: date(2026, 8, 18, hour: 9)
        )
        XCTAssertEqual(updated.current.totalPlayDelta, 4)
        XCTAssertEqual(updated.previous?.totalPlayDelta, 8)
    }

    func testMonthBoundaryWithinAWeekStartsFromNewMonthTotals() {
        let directory = temporaryDirectory()
        let store = WeeklyRecapInsightStore(directoryURL: directory, calendar: calendar)

        _ = store.record(
            recap: recap(year: 2026, month: 1, plays: 120, songPlays: 40),
            at: date(2026, 1, 30, hour: 9)
        )
        let result = store.record(
            recap: recap(year: 2026, month: 2, plays: 3, songPlays: 3),
            at: date(2026, 2, 1, hour: 9)
        )

        XCTAssertEqual(result.current.totalPlayDelta, 3)
        XCTAssertEqual(result.current.topSong?.playDelta, 3)
    }

    func testMissingWeekIsNotPresentedAsLastWeek() {
        let directory = temporaryDirectory()
        let store = WeeklyRecapInsightStore(directoryURL: directory, calendar: calendar)

        _ = store.record(
            recap: recap(month: 8, plays: 10, songPlays: 5),
            at: date(2026, 8, 3, hour: 9)
        )
        _ = store.record(
            recap: recap(month: 8, plays: 15, songPlays: 10),
            at: date(2026, 8, 4, hour: 9)
        )
        let result = store.record(
            recap: recap(month: 8, plays: 30, songPlays: 25),
            at: date(2026, 8, 17, hour: 9)
        )

        XCTAssertNil(result.previous)
    }

    func testWeeklyInsightsPersistInCompactStore() {
        let directory = temporaryDirectory()
        let monday = date(2026, 8, 10, hour: 9)
        var store: WeeklyRecapInsightStore? = WeeklyRecapInsightStore(directoryURL: directory, calendar: calendar)
        _ = store?.record(recap: recap(month: 8, plays: 10, songPlays: 4), at: monday)
        _ = store?.record(
            recap: recap(month: 8, plays: 16, songPlays: 10),
            at: date(2026, 8, 11, hour: 9)
        )
        store = nil

        let reloaded = WeeklyRecapInsightStore(directoryURL: directory, calendar: calendar)
        let comparison = reloaded.currentComparison(at: date(2026, 8, 12, hour: 9))
        XCTAssertEqual(comparison.current.totalPlayDelta, 6)
        XCTAssertEqual(comparison.current.topSong?.title, "Glass Rain")
    }

    func testMilestonesAreAutomaticAcrossOverallAndMediaCategories() {
        let recap = recap(month: 8, plays: 520, songPlays: 120, listeningHours: 62)
        let milestones = RecapMilestoneEngine.earnedMilestones(for: recap, periodName: "August 2026")

        XCTAssertEqual(milestones.count, 5)
        XCTAssertEqual(milestones[0].title, "500 plays")
        XCTAssertEqual(milestones[1].title, "50 listening hours")
        XCTAssertEqual(milestones[2].title, "100 plays with Glass Rain")
        XCTAssertEqual(milestones[3].kind, .album)
        XCTAssertEqual(milestones[4].kind, .artist)
    }

    private func recap(
        year: Int = 2026,
        month: Int,
        plays: Int,
        songPlays: Int,
        listeningHours: Int? = nil
    ) -> MonthlyRecap {
        let monthStart = date(year, month, 1)
        let duration = listeningHours.map { TimeInterval($0 * 3_600) } ?? TimeInterval(plays * 180)
        let song = MonthlyRecap.RankedSong(
            id: 1,
            title: "Glass Rain",
            artist: "Nova Lane",
            albumTitle: "Afterimages",
            playDelta: songPlays,
            skipDelta: 0,
            listeningDuration: TimeInterval(songPlays * 180),
            artwork: nil,
            recordingIdentity: "store:1"
        )
        return MonthlyRecap(
            monthStart: monthStart,
            generatedAt: monthStart,
            lastCaptureReason: .manualRefresh,
            trackingStart: monthStart,
            snapshotCount: 2,
            totalPlayDelta: plays,
            totalSkipDelta: 0,
            totalListeningDuration: duration,
            playedSongCount: 1,
            newSongCount: 0,
            topSongs: [song],
            topArtists: [
                MonthlyRecap.RankedGroup(
                    id: "artist:nova-lane",
                    title: "Nova Lane",
                    subtitle: "Artist",
                    playDelta: songPlays,
                    listeningDuration: song.listeningDuration,
                    artwork: nil
                )
            ],
            topAlbums: [
                MonthlyRecap.RankedGroup(
                    id: "album:afterimages",
                    title: "Afterimages",
                    subtitle: "Nova Lane",
                    playDelta: songPlays,
                    listeningDuration: song.listeningDuration,
                    artwork: nil
                )
            ],
            biggestGainers: [],
            topNewSongs: []
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeeklyRecapInsightsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
