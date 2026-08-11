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
        XCTAssertEqual(updated.history.map(\.totalPlayDelta), [8, 4])
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
        let recap = recap(
            month: 8,
            plays: 520,
            songPlays: 120,
            listeningHours: 62,
            playedSongCount: 180,
            artistCount: 263,
            songHours: 24,
            albumHours: 12,
            artistHours: 30
        )
        let milestones = RecapMilestoneEngine.milestones(for: recap, periodName: "August 2026")

        XCTAssertEqual(milestones.count, 6)
        XCTAssertEqual(milestones[0].title, "World Tour")
        XCTAssertEqual(milestones[0].valueLabel, "263 of 500 artists")
        XCTAssertEqual(milestones[0].earnedTarget, 250)
        XCTAssertEqual(milestones[0].stage, 5)
        XCTAssertEqual(milestones[1].title, "Deep Catalog")
        XCTAssertEqual(milestones[1].targetValue, 250)
        XCTAssertEqual(milestones[2].title, "Permanent Headphones")
        XCTAssertEqual(milestones[3].title, "Two-Day Obsession")
        XCTAssertEqual(milestones[3].earnedTarget, 24)
        XCTAssertEqual(milestones[4].kind, .albumHome)
        XCTAssertEqual(milestones[5].kind, .artistEra)
    }

    func testDetailMilestonesUseAllTimePlaysAndListeningDuration() {
        let song = MediaMilestoneEngine.song(
            playCount: 63,
            listeningDuration: 24 * 3_600,
            title: "Glass Rain"
        )
        XCTAssertEqual(song.map(\.kind), [.songPlays, .songListeningTime])
        XCTAssertEqual(song[0].title, "Heavy Rotation")
        XCTAssertEqual(song[0].compactValueLabel, "63 / 100 plays")
        XCTAssertEqual(song[0].stage, 3)
        XCTAssertEqual(song[1].title, "Permanent Favorite")
        XCTAssertEqual(song[1].compactValueLabel, "24 / 48 hours")
        XCTAssertEqual(song[1].stage, 5)

        let album = MediaMilestoneEngine.album(
            playCount: 520,
            listeningDuration: 50 * 3_600,
            title: "Afterimages"
        )
        XCTAssertEqual(album.map(\.kind), [.albumPlays, .albumListeningTime])
        XCTAssertEqual(album[0].targetValue, 1_000)
        XCTAssertEqual(album[1].targetValue, 100)

        let artist = MediaMilestoneEngine.artist(
            playCount: 2_600,
            listeningDuration: 251 * 3_600,
            name: "Nova Lane"
        )
        XCTAssertEqual(artist.map(\.kind), [.artistPlays, .artistListeningTime])
        XCTAssertEqual(artist[0].targetValue, 5_000)
        XCTAssertEqual(artist[0].stage, 6)
        XCTAssertEqual(artist[1].targetValue, 500)
    }

    private func recap(
        year: Int = 2026,
        month: Int,
        plays: Int,
        songPlays: Int,
        listeningHours: Int? = nil,
        playedSongCount: Int = 1,
        artistCount: Int = 1,
        songHours: Int? = nil,
        albumHours: Int? = nil,
        artistHours: Int? = nil
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
            listeningDuration: songHours.map { TimeInterval($0 * 3_600) } ?? TimeInterval(songPlays * 180),
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
            playedSongCount: playedSongCount,
            listenedArtistCount: artistCount,
            newSongCount: 0,
            topSongs: [song],
            topArtists: (0..<artistCount).map { index in
                MonthlyRecap.RankedGroup(
                    id: "artist:\(index)",
                    title: index == 0 ? "Nova Lane" : "Artist \(index + 1)",
                    subtitle: "Artist",
                    playDelta: index == 0 ? songPlays : 1,
                    listeningDuration: index == 0
                        ? (artistHours.map { TimeInterval($0 * 3_600) } ?? song.listeningDuration)
                        : 180,
                    artwork: nil
                )
            },
            topAlbums: [
                MonthlyRecap.RankedGroup(
                    id: "album:afterimages",
                    title: "Afterimages",
                    subtitle: "Nova Lane",
                    playDelta: songPlays,
                    listeningDuration: albumHours.map { TimeInterval($0 * 3_600) } ?? song.listeningDuration,
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
