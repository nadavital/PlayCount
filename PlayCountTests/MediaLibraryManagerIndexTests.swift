import XCTest
@testable import PlayCount

final class MediaLibraryManagerIndexTests: XCTestCase {
    func testAlbumsForArtistMergesIDAndNameMatches() {
        let artist = artist(id: 10, name: "Nova Lane")
        let manager = manager(
            songs: [],
            albums: [
                album(id: 1, title: "ID Match", artist: "Nova Lane", playCount: 40, artistPersistentID: 10),
                album(id: 2, title: "Name Match", artist: "Nova Lane", playCount: 90, artistPersistentID: 999),
                album(id: 3, title: "Other Artist", artist: "Mira Vale", playCount: 120, artistPersistentID: 20)
            ],
            artists: [artist]
        )

        XCTAssertEqual(manager.albums(for: artist).map(\.title), ["Name Match", "ID Match"])
    }

    func testSongsForArtistPreservesZeroIDNameFallbackWhenIDMatchesExist() {
        let artist = artist(id: 10, name: "Nova Lane")
        let manager = manager(
            songs: [
                song(id: 1, title: "ID Song", artist: "Nova Lane", playCount: 40, artistPersistentID: 10),
                song(id: 2, title: "Fallback Song", artist: "Nova Lane", playCount: 90, artistPersistentID: 0),
                song(id: 3, title: "Different ID Song", artist: "Nova Lane", playCount: 120, artistPersistentID: 999)
            ],
            albums: [],
            artists: [artist]
        )

        XCTAssertEqual(manager.songs(for: artist).map(\.title), ["Fallback Song", "ID Song"])
    }

    func testSongsForAlbumMergesIDAndLegacyZeroIDFallbackMatches() {
        let album = album(id: 100, title: "Glass Coast", artist: "Nova Lane", playCount: 40, artistPersistentID: 10)
        let manager = manager(
            songs: [
                song(id: 1, title: "ID Track", artist: "Nova Lane", albumTitle: "Glass Coast", playCount: 40, albumPersistentID: 100, artistPersistentID: 10),
                song(id: 2, title: "Fallback Track", artist: "Nova Lane", albumTitle: "Glass Coast", playCount: 90, albumPersistentID: 0, artistPersistentID: 10),
                song(id: 3, title: "Other Track", artist: "Mira Vale", albumTitle: "Glass Coast", playCount: 120, albumPersistentID: 0, artistPersistentID: 20)
            ],
            albums: [album],
            artists: [artist(id: 10, name: "Nova Lane")]
        )

        XCTAssertEqual(manager.songs(for: album).map(\.title), ["Fallback Track", "ID Track"])
    }

    func testRankMapsUseSameTieBreakersAsVisibleSongOrder() {
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let shorterRecentSong = song(
            id: 1,
            title: "Shorter Recent Song",
            artist: "Nova Lane",
            playCount: 10,
            totalPlayDuration: 100,
            lastPlayedDate: newerDate,
            artistPersistentID: 10
        )
        let longerOlderSong = song(
            id: 2,
            title: "Longer Older Song",
            artist: "Nova Lane",
            playCount: 10,
            totalPlayDuration: 200,
            lastPlayedDate: olderDate,
            artistPersistentID: 10
        )
        let manager = manager(
            songs: [shorterRecentSong, longerOlderSong],
            albums: [],
            artists: [artist(id: 10, name: "Nova Lane")]
        )

        XCTAssertEqual(manager.topSongs.map(\.title), ["Longer Older Song", "Shorter Recent Song"])
        XCTAssertEqual(manager.playCountRank(of: longerOlderSong), 1)
        XCTAssertEqual(manager.playCountRank(of: shorterRecentSong), 2)

        manager.sortMetric = .listenTime

        XCTAssertEqual(manager.topSongs.map(\.title), ["Longer Older Song", "Shorter Recent Song"])
        XCTAssertEqual(manager.listenTimeRank(of: longerOlderSong), 1)
        XCTAssertEqual(manager.listenTimeRank(of: shorterRecentSong), 2)
    }

    func testRankMapsUseSameTieBreakersAsVisibleAlbumAndArtistOrder() {
        let zAlbum = album(id: 1, title: "Z Album", artist: "Nova Lane", playCount: 10, totalPlayDuration: 100, artistPersistentID: 10)
        let aAlbum = album(id: 2, title: "A Album", artist: "Nova Lane", playCount: 10, totalPlayDuration: 100, artistPersistentID: 10)
        let zArtist = artist(id: 10, name: "Z Artist", playCount: 10, totalPlayDuration: 100)
        let aArtist = artist(id: 11, name: "A Artist", playCount: 10, totalPlayDuration: 100)
        let manager = manager(
            songs: [],
            albums: [zAlbum, aAlbum],
            artists: [zArtist, aArtist]
        )

        XCTAssertEqual(manager.topAlbums.map(\.title), ["A Album", "Z Album"])
        XCTAssertEqual(manager.playCountRank(of: aAlbum), 1)
        XCTAssertEqual(manager.playCountRank(of: zAlbum), 2)
        XCTAssertEqual(manager.topArtists.map(\.name), ["A Artist", "Z Artist"])
        XCTAssertEqual(manager.playCountRank(of: aArtist), 1)
        XCTAssertEqual(manager.playCountRank(of: zArtist), 2)
    }

    func testYearlyPlayedSongCountIncludesSyncedTopNewSongsOutsideTopSongCap() {
        let sourceStore = makeStore(named: "yearly-source")
        let targetStore = makeStore(named: "yearly-target")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)
        let newSongDate = date(year: 2026, month: 5, day: 7)
        let baselineSongs = (1...260).map {
            song(id: UInt64($0), title: "Existing Song \($0)", artist: "Artist", playCount: 10, artistPersistentID: 20)
        }
        var latestSongs = baselineSongs.map {
            song(id: $0.id, title: $0.title, artist: $0.artist, playCount: $0.playCount + 1, artistPersistentID: $0.artistPersistentID)
        }
        latestSongs.append(
            song(
                id: 9_001,
                title: "Low Delta New Song",
                artist: "Artist",
                playCount: 1,
                dateAdded: newSongDate,
                artistPersistentID: 20
            )
        )

        _ = sourceStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = sourceStore.record(songs: latestSongs, at: latestDate, reason: .foreground)
        XCTAssertTrue(targetStore.mergeSyncPayloads(sourceStore.localSyncPayloads(), now: latestDate))

        let manager = MediaLibraryManager(
            snapshotStore: targetStore,
            recapCloudSyncService: nil,
            startsAutomatically: false
        )
        let yearlyRecap = manager.yearlyRecap(for: 2026)

        XCTAssertEqual(yearlyRecap.topSongs.count, 250)
        XCTAssertEqual(yearlyRecap.topNewSongs.first?.title, "Low Delta New Song")
        XCTAssertEqual(yearlyRecap.playedSongCount, 261)
    }

    private func manager(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist]
    ) -> MediaLibraryManager {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        manager.debugLoadLibraryFixture(songs: songs, albums: albums, artists: artists)
        return manager
    }

    private func makeStore(named name: String) -> MonthlyRecapSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountManagerIndexTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        return MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: name
        )
    }

    private func song(
        id: UInt64,
        title: String,
        artist: String,
        albumTitle: String = "Album",
        playCount: Int,
        totalPlayDuration: TimeInterval? = nil,
        lastPlayedDate: Date? = nil,
        dateAdded: Date? = nil,
        albumPersistentID: UInt64 = 1,
        artistPersistentID: UInt64
    ) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            playCount: playCount,
            skipCount: 0,
            totalPlayDuration: totalPlayDuration ?? TimeInterval(playCount * 180),
            playbackDuration: 180,
            lastPlayedDate: lastPlayedDate,
            dateAdded: dateAdded,
            artwork: nil,
            albumPersistentID: albumPersistentID,
            artistPersistentID: artistPersistentID,
            trackNumber: 1
        )
    }

    private func album(
        id: UInt64,
        title: String,
        artist: String,
        playCount: Int,
        totalPlayDuration: TimeInterval? = nil,
        artistPersistentID: UInt64
    ) -> TopAlbum {
        TopAlbum(
            id: id,
            title: title,
            artist: artist,
            playCount: playCount,
            totalPlayDuration: totalPlayDuration ?? TimeInterval(playCount * 180),
            artwork: nil,
            artistPersistentID: artistPersistentID
        )
    }

    private func artist(
        id: UInt64,
        name: String,
        playCount: Int = 0,
        totalPlayDuration: TimeInterval = 0
    ) -> TopArtist {
        TopArtist(
            id: id,
            name: name,
            playCount: playCount,
            totalPlayDuration: totalPlayDuration,
            artwork: nil
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        ).date!
    }
}
