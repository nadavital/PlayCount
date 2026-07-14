import XCTest
@testable import PlayCount

final class PlayCountAppIntentTests: XCTestCase {
    func testSongEntityPreservesStableIdentityAndStatistics() {
        let song = makeSong(id: 42, title: "Holocene", artist: "Bon Iver", album: "Bon Iver", plays: 17, duration: 238)
        let entity = SongEntity(song: song)

        XCTAssertEqual(entity.id, "42")
        XCTAssertEqual(entity.title, "Holocene")
        XCTAssertEqual(entity.artist, "Bon Iver")
        XCTAssertEqual(entity.album, "Bon Iver")
        XCTAssertEqual(entity.playCount, 17)
        XCTAssertEqual(entity.listeningTime, 4_046)
    }

    func testRankingIsExplicitAndIndependentOfAppSortState() {
        let mostPlayed = makeSong(id: 1, title: "Most Played", plays: 12, duration: 60)
        let longest = makeSong(id: 2, title: "Longest", plays: 3, duration: 600)

        XCTAssertEqual(PlayCountIntentRanking.topSongs(from: [longest, mostPlayed], metric: .plays, limit: 1).map(\.id), [1])
        XCTAssertEqual(PlayCountIntentRanking.topSongs(from: [longest, mostPlayed], metric: .listeningTime, limit: 1).map(\.id), [2])
    }

    func testSongSearchMatchesTitleArtistAndAlbumAndRanksResults() {
        let titleMatch = makeSong(id: 1, title: "Northern Sky", artist: "Nick Drake", album: "Bryter Layter", plays: 9)
        let artistMatch = makeSong(id: 2, title: "Pink Moon", artist: "Nick Drake", album: "Pink Moon", plays: 20)
        let albumMatch = makeSong(id: 3, title: "Hazey Jane II", artist: "Nick Drake", album: "Bryter Layter", plays: 4)

        XCTAssertEqual(
            PlayCountIntentRanking.matchingSongs([titleMatch, artistMatch, albumMatch], search: "Bryter").map(\.id),
            [1, 3]
        )
        XCTAssertEqual(
            PlayCountIntentRanking.matchingSongs([titleMatch, artistMatch, albumMatch], search: "Nick Drake").map(\.id),
            [2, 1, 3]
        )
    }

    func testDuplicateSongTitlesRemainDistinctEntities() {
        let first = SongEntity(song: makeSong(id: 11, title: "Home", artist: "Artist A"))
        let second = SongEntity(song: makeSong(id: 12, title: "Home", artist: "Artist B"))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.artist, second.artist)
    }

    func testLatestRecapNavigationRequestIsConsumedOnce() {
        _ = PlayCountNavigationRequestStore.consumeLatestRecapRequest()
        _ = PlayCountNavigationRequestStore.consumeRequestedRecapMonth()
        let month = Date(timeIntervalSinceReferenceDate: 123_456)
        PlayCountNavigationRequestStore.requestLatestRecap(monthStart: month)

        XCTAssertTrue(PlayCountNavigationRequestStore.consumeLatestRecapRequest())
        XCTAssertFalse(PlayCountNavigationRequestStore.consumeLatestRecapRequest())
        XCTAssertEqual(PlayCountNavigationRequestStore.consumeRequestedRecapMonth(), month)
        XCTAssertNil(PlayCountNavigationRequestStore.consumeRequestedRecapMonth())
    }

    func testLatestUsableRecapFallsBackAcrossMonthBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = MonthlyRecap.empty(for: Date(timeIntervalSince1970: 1_772_323_200), calendar: calendar)
        let previousMonth = makeRecap(monthStart: Date(timeIntervalSince1970: 1_769_904_000), plays: 12)

        XCTAssertEqual(
            PlayCountIntentRecaps.latestUsable(from: [previousMonth, currentMonth])?.monthStart,
            previousMonth.monthStart
        )
    }

    func testSearchFingerprintChangesForIndexedMetadataAndListeningTime() {
        let original = makeSong(id: 1, title: "Original", artist: "Artist", plays: 2, duration: 60)
        let renamed = makeSong(id: 1, title: "Renamed", artist: "Artist", plays: 2, duration: 60)
        let newArtist = makeSong(id: 1, title: "Original", artist: "Other Artist", plays: 2, duration: 60)
        let longer = makeSong(id: 1, title: "Original", artist: "Artist", plays: 2, duration: 90)
        let baseline = PlayCountSearchFingerprint.make(songs: [original], albums: [], artists: [])

        XCTAssertNotEqual(baseline, PlayCountSearchFingerprint.make(songs: [renamed], albums: [], artists: []))
        XCTAssertNotEqual(baseline, PlayCountSearchFingerprint.make(songs: [newArtist], albums: [], artists: []))
        XCTAssertNotEqual(baseline, PlayCountSearchFingerprint.make(songs: [longer], albums: [], artists: []))
    }

    func testIntentLibraryCacheLoadsOneSnapshotForResolutionChain() {
        let counter = LockedCounter()
        let cache = PlayCountIntentLibraryCache(lifetime: 5) {
            counter.increment()
            return PlayCountIntentLibrarySnapshot(songs: [], albums: [], artists: [])
        }

        _ = cache.snapshot(now: Date(timeIntervalSince1970: 100))
        _ = cache.snapshot(now: Date(timeIntervalSince1970: 102))

        XCTAssertEqual(counter.value, 1)
    }

    @available(iOS 27.0, *)
    func testCompilationAlbumUsesResolvableAlbumArtistIdentity() {
        let song = makeSong(
            id: 1,
            title: "Duet",
            artist: "Guest Artist",
            albumArtist: "Various Artists"
        )
        let album = SiriAIAlbumEntity(song: song)
        let expectedArtist = SiriAIArtistEntity(persistentID: 0, name: "Various Artists")

        XCTAssertEqual(album.artistName, "Various Artists")
        XCTAssertEqual(album.artists.map(\.id), [expectedArtist.id])
    }

    @available(iOS 27.0, *)
    func testAlbumArtistIdentityIgnoresCaseDifferences() {
        let song = makeSong(id: 1, title: "Song", artist: "The Artist", albumArtist: "the artist")
        let album = SiriAIAlbumEntity(song: song)

        XCTAssertEqual(album.artists.map(\.id), [String(song.artistPersistentID)])
    }

    private func makeSong(
        id: UInt64,
        title: String,
        artist: String = "Artist",
        albumArtist: String? = nil,
        album: String = "Album",
        plays: Int = 1,
        duration: TimeInterval = 180
    ) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: artist,
            albumTitle: album,
            albumArtist: albumArtist ?? artist,
            playCount: plays,
            skipCount: 0,
            totalPlayDuration: Double(plays) * duration,
            playbackDuration: duration,
            lastPlayedDate: nil,
            dateAdded: nil,
            artwork: nil,
            albumPersistentID: id + 100,
            artistPersistentID: id + 200,
            trackNumber: 1
        )
    }

    private func makeRecap(monthStart: Date, plays: Int) -> MonthlyRecap {
        MonthlyRecap(
            monthStart: monthStart,
            generatedAt: monthStart,
            lastCaptureReason: nil,
            trackingStart: monthStart,
            snapshotCount: 2,
            totalPlayDelta: plays,
            totalSkipDelta: 0,
            totalListeningDuration: 1_200,
            playedSongCount: 1,
            newSongCount: 0,
            topSongs: [
                MonthlyRecap.RankedSong(
                    id: 1,
                    title: "Song",
                    artist: "Artist",
                    albumTitle: "Album",
                    playDelta: plays,
                    skipDelta: 0,
                    listeningDuration: 1_200,
                    artwork: nil
                )
            ],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            topNewSongs: []
        )
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}
