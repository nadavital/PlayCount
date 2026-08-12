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
        let groups = MilestoneCollectionPresentation.groups(from: milestones)
        let artistMilestones = groups[0]
        let visibleMilestones = MilestoneCollectionPresentation.visibleMilestones(from: milestones)

        XCTAssertEqual(groups.count, 6)
        XCTAssertEqual(milestones.count, 47)
        XCTAssertEqual(artistMilestones.map(\.title), [
            "10 Artists", "25 Artists", "50 Artists", "100 Artists",
            "250 Artists", "500 Artists", "1,000 Artists"
        ])
        XCTAssertEqual(artistMilestones.filter(\.isEarned).map(\.targetValue), [10, 25, 50, 100, 250])
        XCTAssertEqual(Set(artistMilestones.map(\.stage)).count, artistMilestones.count)
        XCTAssertEqual(artistMilestones.suffix(3).map(\.stage), [6, 7, 8])
        XCTAssertFalse(artistMilestones[5].isEarned)
        XCTAssertEqual(artistMilestones[5].compactValueLabel, "263 of 500 artists")
        XCTAssertEqual(visibleMilestones.filter { $0.kind == .artistDiscovery }.count, 6)
        XCTAssertEqual(Set(milestones.map(\.id)).count, milestones.count)
    }

    func testDetailMilestonesUseAllTimePlaysAndListeningDuration() {
        let song = MediaMilestoneEngine.song(
            playCount: 63,
            listeningDuration: 24 * 3_600,
            title: "Glass Rain"
        )
        let songGroups = MilestoneCollectionPresentation.groups(from: song)
        XCTAssertEqual(songGroups.count, 2)
        XCTAssertEqual(song.count, 16)
        XCTAssertEqual(Set(songGroups[0].map(\.stage)).count, songGroups[0].count)
        XCTAssertEqual(songGroups[0].suffix(3).map(\.stage), [6, 7, 8])
        XCTAssertEqual(songGroups[0].filter(\.isEarned).map(\.title), ["10 Plays", "25 Plays", "50 Plays"])
        XCTAssertEqual(songGroups[0].first { !$0.isEarned }?.title, "100 Plays")
        XCTAssertEqual(songGroups[1].filter(\.isEarned).last?.title, "24 Hours")
        XCTAssertEqual(songGroups[1].first { !$0.isEarned }?.compactValueLabel, "24 of 48 hours")

        let album = MediaMilestoneEngine.album(
            playCount: 520,
            listeningDuration: 50 * 3_600,
            title: "Afterimages"
        )
        let albumGroups = MilestoneCollectionPresentation.groups(from: album)
        XCTAssertEqual(albumGroups.count, 2)
        XCTAssertEqual(albumGroups[0].first { !$0.isEarned }?.targetValue, 1_000)
        XCTAssertEqual(albumGroups[1].first { !$0.isEarned }?.targetValue, 100)

        let artist = MediaMilestoneEngine.artist(
            playCount: 2_600,
            listeningDuration: 251 * 3_600,
            name: "Nova Lane"
        )
        let artistGroups = MilestoneCollectionPresentation.groups(from: artist)
        XCTAssertEqual(artistGroups.count, 2)
        XCTAssertEqual(artistGroups[0].first { !$0.isEarned }?.targetValue, 5_000)
        XCTAssertEqual(artistGroups[1].first { !$0.isEarned }?.targetValue, 500)
    }

    func testExactThresholdEarnsCurrentStageAndAdvancesDisplayedTarget() {
        let milestones = MediaMilestoneEngine.song(
            playCount: 50,
            listeningDuration: 3 * 3_600,
            title: "Glass Rain"
        )

        let groups = MilestoneCollectionPresentation.groups(from: milestones)
        let plays50 = try? XCTUnwrap(groups[0].first { $0.targetValue == 50 })
        let plays100 = try? XCTUnwrap(groups[0].first { $0.targetValue == 100 })
        let hours3 = try? XCTUnwrap(groups[1].first { $0.targetValue == 3 })
        let hours6 = try? XCTUnwrap(groups[1].first { $0.targetValue == 6 })

        XCTAssertTrue(plays50?.isEarned == true)
        XCTAssertEqual(plays50?.valueLabel, "50 plays earned")
        XCTAssertFalse(plays100?.isEarned == true)
        XCTAssertEqual(plays100?.statusLabel, "Milestone locked")
        XCTAssertEqual(plays100?.compactValueLabel, "50 of 100 plays")
        XCTAssertTrue(hours3?.isEarned == true)
        XCTAssertFalse(hours6?.isEarned == true)
    }

    func testEveryMilestonePathUsesUniqueVisualTiersAndEndsWithSpecialThree() {
        let recap = recap(
            month: 8,
            plays: 1,
            songPlays: 1,
            playedSongCount: 1,
            artistCount: 1,
            songHours: 1,
            albumHours: 1,
            artistHours: 1
        )
        let recapGroups = MilestoneCollectionPresentation.groups(
            from: RecapMilestoneEngine.milestones(for: recap, periodName: "2026")
        )
        let detailGroups = [
            MediaMilestoneEngine.song(playCount: 1, listeningDuration: 0, title: "Song"),
            MediaMilestoneEngine.album(playCount: 1, listeningDuration: 0, title: "Album"),
            MediaMilestoneEngine.artist(playCount: 1, listeningDuration: 0, name: "Artist")
        ].flatMap { MilestoneCollectionPresentation.groups(from: $0) }

        for group in recapGroups + detailGroups {
            XCTAssertEqual(Set(group.map(\.stage)).count, group.count)
            XCTAssertEqual(group.suffix(3).map(\.stage), [6, 7, 8])
        }
    }

    func testMonthlyPresentationShowsOnlyThresholdsNewlyEarnedSincePreviousMonth() {
        let previous = MediaMilestoneEngine.artist(
            playCount: 90,
            listeningDuration: 9 * 3_600,
            name: "Nova Lane"
        )
        let current = MediaMilestoneEngine.artist(
            playCount: 275,
            listeningDuration: 26 * 3_600,
            name: "Nova Lane"
        )

        let unlocked = MilestoneCollectionPresentation.newlyEarned(
            current: current,
            previous: previous
        )

        XCTAssertEqual(unlocked.filter { $0.kind == .artistPlays }.map(\.title), ["100 Plays", "250 Plays"])
        XCTAssertEqual(unlocked.filter { $0.kind == .artistListeningTime }.map(\.title), ["10 Hours", "25 Hours"])
        XCTAssertTrue(unlocked.allSatisfy(\.isEarned))
    }

    func testDetailProgressSummariesUseHighestEarnedMedalAndNextThreshold() {
        let milestones = MediaMilestoneEngine.song(
            playCount: 63,
            listeningDuration: 24 * 3_600,
            title: "Glass Rain"
        )
        let summaries = MilestoneCollectionPresentation.progressSummary(from: milestones)

        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].highestEarned?.title, "50 Plays")
        XCTAssertEqual(summaries[0].featured.title, "50 Plays")
        XCTAssertEqual(summaries[0].next?.title, "100 Plays")
        XCTAssertEqual(summaries[1].highestEarned?.title, "24 Hours")
        XCTAssertEqual(summaries[1].next?.title, "48 Hours")
    }

    func testMediaMilestoneLedgerPreservesHighestValuesAcrossCountRegression() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("milestones.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let ledger = MediaMilestoneLedger(fileURL: fileURL)
        ledger.observe(
            scope: .song,
            identity: "store:123",
            playCount: 320,
            listeningDuration: 86_400,
            at: Date(timeIntervalSince1970: 10)
        )
        ledger.observe(
            scope: .song,
            identity: "store:123",
            playCount: 12,
            listeningDuration: 3_600,
            at: Date(timeIntervalSince1970: 20)
        )

        let values = ledger.highestObserved(
            scope: .song,
            identity: "store:123",
            currentPlayCount: 18,
            currentListeningDuration: 7_200
        )
        XCTAssertEqual(values.playCount, 320)
        XCTAssertEqual(values.listeningDuration, 86_400)

        let restoredLedger = MediaMilestoneLedger(fileURL: fileURL)
        restoredLedger.hydrateCache()
        let restoredValues = restoredLedger.highestObserved(
            scope: .song,
            identity: "store:123",
            currentPlayCount: 18,
            currentListeningDuration: 7_200
        )
        XCTAssertEqual(restoredValues.playCount, 320)
        XCTAssertEqual(restoredValues.listeningDuration, 86_400)
    }

    func testSongMilestoneIdentitySeparatesRecordingsButSurvivesLibraryReaddition() {
        func song(id: UInt64, album: String, storeID: String = "") -> TopSong {
            TopSong(
                id: id,
                title: "Echoes",
                artist: "Nova Lane",
                albumTitle: album,
                albumArtist: "Nova Lane",
                playCount: 1,
                skipCount: 0,
                totalPlayDuration: 180,
                playbackDuration: 180,
                lastPlayedDate: nil,
                dateAdded: nil,
                artwork: nil,
                albumPersistentID: 0,
                artistPersistentID: 0,
                trackNumber: 1,
                playbackStoreID: storeID
            )
        }

        let studio = song(id: 1, album: "Echoes")
        let live = song(id: 2, album: "Echoes Live")
        XCTAssertNotEqual(MediaMilestoneLedger.songIdentity(studio), MediaMilestoneLedger.songIdentity(live))

        let beforeDeletion = song(id: 3, album: "Echoes", storeID: "12345")
        let afterReaddition = song(id: 99, album: "Echoes (Deluxe)", storeID: "12345")
        XCTAssertEqual(
            MediaMilestoneLedger.songIdentity(beforeDeletion),
            MediaMilestoneLedger.songIdentity(afterReaddition)
        )

        let firstAlbum = TopAlbum(
            id: 10,
            title: "Greatest Hits",
            artist: "Nova Lane",
            playCount: 1,
            totalPlayDuration: 180,
            artwork: nil,
            artistPersistentID: 20
        )
        let secondAlbum = TopAlbum(
            id: 11,
            title: "Greatest Hits",
            artist: "Nova Lane",
            playCount: 1,
            totalPlayDuration: 180,
            artwork: nil,
            artistPersistentID: 20
        )
        XCTAssertNotEqual(
            MediaMilestoneLedger.albumIdentity(firstAlbum),
            MediaMilestoneLedger.albumIdentity(secondAlbum)
        )
        XCTAssertTrue(
            Set(MediaMilestoneLedger.albumIdentities(firstAlbum, includesMetadataAlias: false))
                .isDisjoint(with: MediaMilestoneLedger.albumIdentities(secondAlbum, includesMetadataAlias: false))
        )

        let firstArtist = TopArtist(
            id: 20,
            name: "Nova",
            playCount: 1,
            totalPlayDuration: 180,
            artwork: nil
        )
        let secondArtist = TopArtist(
            id: 21,
            name: "Nova",
            playCount: 1,
            totalPlayDuration: 180,
            artwork: nil
        )
        XCTAssertNotEqual(
            MediaMilestoneLedger.artistIdentity(firstArtist),
            MediaMilestoneLedger.artistIdentity(secondArtist)
        )
        XCTAssertTrue(
            Set(MediaMilestoneLedger.artistIdentities(firstArtist, includesMetadataAlias: false))
                .isDisjoint(with: MediaMilestoneLedger.artistIdentities(secondArtist, includesMetadataAlias: false))
        )
    }

    func testAmbiguousAlbumAliasesDoNotShareMilestoneValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("milestones.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = TopAlbum(
            id: 10, title: "Greatest Hits", artist: "Nova Lane", playCount: 500,
            totalPlayDuration: 50_000, artwork: nil, artistPersistentID: 20
        )
        let second = TopAlbum(
            id: 11, title: "Greatest Hits", artist: "Nova Lane", playCount: 12,
            totalPlayDuration: 1_000, artwork: nil, artistPersistentID: 20
        )
        let ledger = MediaMilestoneLedger(fileURL: fileURL)
        ledger.observe(songs: [], albums: [first, second], artists: [])

        let secondValues = ledger.highestObserved(
            scope: .album,
            identities: MediaMilestoneLedger.albumIdentities(second, includesMetadataAlias: false),
            currentPlayCount: second.playCount,
            currentListeningDuration: second.totalPlayDuration
        )
        XCTAssertEqual(secondValues.playCount, 12)
        XCTAssertEqual(secondValues.listeningDuration, 1_000)
    }

    func testReaddedAlbumMigratesAliasMaximumBeforeAliasBecomesAmbiguous() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("milestones.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        func album(id: UInt64, plays: Int) -> TopAlbum {
            TopAlbum(
                id: id, title: "Greatest Hits", artist: "Nova Lane", playCount: plays,
                totalPlayDuration: TimeInterval(plays * 180), artwork: nil, artistPersistentID: 20
            )
        }
        let ledger = MediaMilestoneLedger(fileURL: fileURL)
        let original = album(id: 10, plays: 500)
        ledger.observe(songs: [], albums: [original], artists: [])
        let aliasOnly = ledger.highestObserved(
            scope: .album,
            identities: [MediaMilestoneLedger.albumMetadataIdentity(original)],
            currentPlayCount: 0,
            currentListeningDuration: 0
        )
        XCTAssertEqual(aliasOnly.playCount, 500)

        let readded = album(id: 11, plays: 12)
        ledger.observe(songs: [], albums: [readded], artists: [])
        let bridgedValues = ledger.highestObserved(
            scope: .album,
            identities: MediaMilestoneLedger.albumIdentities(readded),
            currentPlayCount: readded.playCount,
            currentListeningDuration: readded.totalPlayDuration
        )
        XCTAssertEqual(bridgedValues.playCount, 500)

        let sibling = album(id: 12, plays: 4)
        ledger.observe(songs: [], albums: [readded, sibling], artists: [])
        let readdedValues = ledger.highestObserved(
            scope: .album,
            identities: MediaMilestoneLedger.albumIdentities(readded, includesMetadataAlias: false),
            currentPlayCount: readded.playCount,
            currentListeningDuration: readded.totalPlayDuration
        )
        let siblingValues = ledger.highestObserved(
            scope: .album,
            identities: MediaMilestoneLedger.albumIdentities(sibling, includesMetadataAlias: false),
            currentPlayCount: sibling.playCount,
            currentListeningDuration: sibling.totalPlayDuration
        )
        XCTAssertEqual(readdedValues.playCount, 500)
        XCTAssertEqual(siblingValues.playCount, 4)
    }

    func testMilestoneLedgerRollsBackWhenCommitBecomesInvalid() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("milestones.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = MediaMilestoneLedger(fileURL: fileURL)
        let song = TopSong(
            id: 1,
            title: "Echoes",
            artist: "Nova Lane",
            albumTitle: "Echoes",
            albumArtist: "Nova Lane",
            playCount: 320,
            skipCount: 0,
            totalPlayDuration: 86_400,
            playbackDuration: 180,
            lastPlayedDate: nil,
            dateAdded: nil,
            artwork: nil,
            albumPersistentID: 10,
            artistPersistentID: 20,
            trackNumber: 1,
            playbackStoreID: "12345"
        )
        let predicateCalls = LockedTestCounter()
        ledger.observe(songs: [song], albums: [], artists: []) {
            predicateCalls.increment() == 1
        }

        let restored = MediaMilestoneLedger(fileURL: fileURL)
        restored.hydrateCache()
        let values = restored.highestObserved(
            scope: .song,
            identity: MediaMilestoneLedger.songIdentity(song),
            currentPlayCount: 0,
            currentListeningDuration: 0
        )
        XCTAssertEqual(values.playCount, 0)
        XCTAssertEqual(values.listeningDuration, 0)
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

private final class LockedTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
