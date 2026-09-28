import XCTest
@testable import PlayCount

final class PlayCountAppIntentTests: XCTestCase {
    func testSearchFingerprintChangesWhenSiriRelationshipsChange() {
        let original = makeSong(id: 1, title: "Track", artistID: 20)
        let reassigned = makeSong(id: 1, title: "Track", artistID: 21)
        let compilation = makeSong(id: 1, title: "Track", albumArtist: "Various Artists", artistID: 20)
        let baseline = PlayCountSearchFingerprint.make(songs: [original], albums: [], artists: [])
        XCTAssertNotEqual(baseline, PlayCountSearchFingerprint.make(songs: [reassigned], albums: [], artists: []))
        XCTAssertNotEqual(baseline, PlayCountSearchFingerprint.make(songs: [compilation], albums: [], artists: []))
    }

    @available(iOS 27.0, *)
    func testSiriAudioSongQueryMatchesAlbumMetadata() async throws {
        let library = siriLibrary(songs: [makeSong(id: 1, title: "Track", artist: "Artist", album: "Quiet Motion", plays: 8)])
        let results = try await SiriAISongEntityQuery(library: library).entities(matching: "  quiet motion  ")
        XCTAssertEqual(results.map(\.title), ["Track"])
        XCTAssertEqual(results.map(\.id), ["1"])
    }

    @available(iOS 27.0, *)
    func testSiriAlbumSearchMatchesArtistAndPreservesRequestedIDOrder() async throws {
        let albums = [makeAlbum(id: 20, title: "Quiet Motion", plays: 4, listeningTime: 720), makeAlbum(id: 21, title: "Loud Motion", plays: 8, listeningTime: 1440)]
        let query = SiriAIAlbumEntityQuery(library: siriLibrary(albums: albums))
        let matches = try await query.entities(matching: " motion ")
        XCTAssertEqual(matches.map(\.id), ["21", "20"])
        let byArtist = try await query.entities(matching: albums[0].artist)
        XCTAssertEqual(byArtist.count, 2)
        let resolved = try await query.entities(for: ["20", "21", "missing"])
        XCTAssertEqual(resolved.map(\.id), ["20", "21"])
        let absent = try await query.entities(matching: "Absent")
        XCTAssertTrue(absent.isEmpty)
    }

    @available(iOS 27.0, *)
    func testSiriArtistSearchWorksWithoutPersistentArtistIDs() async throws {
        let songs = [makeSong(id: 1, title: "First", artist: "Björk", artistID: 0), makeSong(id: 2, title: "Second", artist: "Björk", artistID: 0)]
        let query = SiriAIArtistEntityQuery(library: siriLibrary(songs: songs))
        let results = try await query.entities(matching: "  bjork  ")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Björk")
        let resolved = try await query.entities(for: results.map(\.id))
        XCTAssertEqual(resolved.map(\.id), results.map(\.id))
    }

    @available(iOS 27.0, *)
    func testSiriSearchChecksAuthorizationBeforeLoadingLibrary() async throws {
        let counter = LockedCounter()
        let cache = PlayCountIntentLibraryCache {
            counter.increment()
            return PlayCountIntentLibrarySnapshot(songs: [], albums: [], artists: [])
        }
        let library = PlayCountIntentLibrary(cache: cache, authorize: { throw PlayCountIntentError.mediaLibraryPermissionRequired })
        do {
            _ = try await SiriAIAlbumEntityQuery(library: library).entities(matching: "Album")
            XCTFail("Unauthorized queries must fail")
        } catch PlayCountIntentError.mediaLibraryPermissionRequired {
            // Expected: no library or cached data was read.
        }
        XCTAssertEqual(counter.value, 0)
    }

    func testSpotlightRebuildRejectsUnauthorizedLibraryBeforeLoading() async throws {
        let counter = LockedCounter()
        let library = PlayCountIntentLibrary(
            cache: PlayCountIntentLibraryCache {
                counter.increment()
                return PlayCountIntentLibrarySnapshot(songs: [], albums: [], artists: [])
            },
            authorize: { throw PlayCountIntentError.mediaLibraryPermissionRequired }
        )
        do {
            try await PlayCountSiriIntegration.reindexSearchEntities(library: library, purge: { counter.increment() })
            XCTFail("Spotlight must not rebuild from an unauthorized library")
        } catch PlayCountIntentError.mediaLibraryPermissionRequired {
            // Expected even if stale index entries had previously existed.
        }
        XCTAssertEqual(counter.value, 1, "Purges stale search data without reading the library")
    }

    private func siriLibrary(songs: [TopSong] = [], albums: [TopAlbum] = [], artists: [TopArtist] = []) -> PlayCountIntentLibrary {
        let cache = PlayCountIntentLibraryCache {
            PlayCountIntentLibrarySnapshot(songs: songs, albums: albums, artists: artists)
        }
        return PlayCountIntentLibrary(cache: cache, authorize: {})
    }

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

    func testAlbumAndArtistRankingSupportsPlaysAndListeningTime() {
        let playedAlbum = makeAlbum(id: 1, title: "Played Album", plays: 12, listeningTime: 720)
        let listenedAlbum = makeAlbum(id: 2, title: "Listened Album", plays: 3, listeningTime: 1_800)
        let playedArtist = makeArtist(id: 3, name: "Played Artist", plays: 20, listeningTime: 1_200)
        let listenedArtist = makeArtist(id: 4, name: "Listened Artist", plays: 8, listeningTime: 3_600)

        XCTAssertEqual(PlayCountIntentRanking.topAlbums(from: [listenedAlbum, playedAlbum], metric: .plays, limit: 1).map(\.id), [1])
        XCTAssertEqual(PlayCountIntentRanking.topAlbums(from: [listenedAlbum, playedAlbum], metric: .listeningTime, limit: 1).map(\.id), [2])
        XCTAssertEqual(PlayCountIntentRanking.topArtists(from: [listenedArtist, playedArtist], metric: .plays, limit: 1).map(\.id), [3])
        XCTAssertEqual(PlayCountIntentRanking.topArtists(from: [listenedArtist, playedArtist], metric: .listeningTime, limit: 1).map(\.id), [4])
    }

    func testAlbumAndArtistEntitiesExposeListeningTime() {
        let album = AlbumEntity(album: makeAlbum(id: 7, title: "Album", plays: 4, listeningTime: 900))
        let artist = ArtistEntity(artist: makeArtist(id: 8, name: "Artist", plays: 5, listeningTime: 1_200))

        XCTAssertEqual(album.listeningTime, 900)
        XCTAssertEqual(artist.listeningTime, 1_200)
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

    func testThisMonthRecapNeverFallsBackToHistoricalActivity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
        let july = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let august = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)))

        XCTAssertNil(
            PlayCountIntentRecaps.currentMonthUsable(
                from: [makeRecap(monthStart: july, plays: 12)],
                now: now,
                calendar: calendar
            )
        )
        XCTAssertEqual(
            PlayCountIntentRecaps.currentMonthUsable(
                from: [makeRecap(monthStart: july, plays: 12), makeRecap(monthStart: august, plays: 4)],
                now: now,
                calendar: calendar
            )?.monthStart,
            august
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
        duration: TimeInterval = 180,
        artistID: UInt64? = nil
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
            artistPersistentID: artistID ?? id + 200,
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

    private func makeAlbum(id: UInt64, title: String, plays: Int, listeningTime: TimeInterval) -> TopAlbum {
        TopAlbum(
            id: id,
            title: title,
            artist: "Artist",
            playCount: plays,
            totalPlayDuration: listeningTime,
            artwork: nil,
            artistPersistentID: id + 100
        )
    }

    private func makeArtist(id: UInt64, name: String, plays: Int, listeningTime: TimeInterval) -> TopArtist {
        TopArtist(
            id: id,
            name: name,
            playCount: plays,
            totalPlayDuration: listeningTime,
            artwork: nil
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
