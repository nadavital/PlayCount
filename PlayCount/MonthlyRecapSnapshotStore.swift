import Foundation
import MediaPlayer

enum RecapSnapshotReason: String, Codable, Equatable {
    case appLaunch
    case foreground
    case delayedForeground
    case manualRefresh
    case backgroundRefresh
    case notificationOpen
    case libraryChanged
    case playbackChanged

    var title: String {
        switch self {
        case .appLaunch:
            return "App launch"
        case .foreground:
            return "App opened"
        case .delayedForeground:
            return "Delayed refresh"
        case .manualRefresh:
            return "Manual refresh"
        case .backgroundRefresh:
            return "Background refresh"
        case .notificationOpen:
            return "Recap reminder"
        case .libraryChanged:
            return "Library changed"
        case .playbackChanged:
            return "Playback changed"
        }
    }
}

struct MonthlyRecap: Equatable {
    struct RankedSong: Identifiable, Equatable {
        let id: UInt64
        let title: String
        let artist: String
        let albumTitle: String
        let playDelta: Int
        let skipDelta: Int
        let listeningDuration: TimeInterval
        let artwork: MPMediaItemArtwork?

        static func == (lhs: RankedSong, rhs: RankedSong) -> Bool {
            lhs.id == rhs.id &&
                lhs.title == rhs.title &&
                lhs.artist == rhs.artist &&
                lhs.albumTitle == rhs.albumTitle &&
                lhs.playDelta == rhs.playDelta &&
                lhs.skipDelta == rhs.skipDelta &&
                lhs.listeningDuration == rhs.listeningDuration
        }
    }

    struct RankedGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let playDelta: Int
        let listeningDuration: TimeInterval
        let artwork: MPMediaItemArtwork?

        static func == (lhs: RankedGroup, rhs: RankedGroup) -> Bool {
            lhs.id == rhs.id &&
                lhs.title == rhs.title &&
                lhs.subtitle == rhs.subtitle &&
                lhs.playDelta == rhs.playDelta &&
                lhs.listeningDuration == rhs.listeningDuration
        }
    }

    struct MovementSong: Identifiable, Equatable {
        let id: UInt64
        let title: String
        let artist: String
        let playDelta: Int
        let rankChange: Int
        let currentRank: Int
        let previousRank: Int?
        let artwork: MPMediaItemArtwork?

        static func == (lhs: MovementSong, rhs: MovementSong) -> Bool {
            lhs.id == rhs.id &&
                lhs.title == rhs.title &&
                lhs.artist == rhs.artist &&
                lhs.playDelta == rhs.playDelta &&
                lhs.rankChange == rhs.rankChange &&
                lhs.currentRank == rhs.currentRank &&
                lhs.previousRank == rhs.previousRank
        }
    }

    let monthStart: Date
    let generatedAt: Date
    let lastCaptureReason: RecapSnapshotReason?
    let trackingStart: Date?
    let snapshotCount: Int
    let totalPlayDelta: Int
    let totalSkipDelta: Int
    let totalListeningDuration: TimeInterval
    let playedSongCount: Int
    let newSongCount: Int
    let topSongs: [RankedSong]
    let topArtists: [RankedGroup]
    let topAlbums: [RankedGroup]
    let biggestGainers: [MovementSong]
    let topNewSongs: [RankedSong]

    var hasActivity: Bool {
        totalPlayDelta > 0 || newSongCount > 0
    }

    var isTrackingOnlyBaseline: Bool {
        snapshotCount <= 1 || (totalPlayDelta == 0 && totalSkipDelta == 0 && newSongCount == 0)
    }

    static func empty(for date: Date, calendar: Calendar = .current) -> MonthlyRecap {
        MonthlyRecap(
            monthStart: calendar.startOfMonth(containing: date),
            generatedAt: date,
            lastCaptureReason: nil,
            trackingStart: nil,
            snapshotCount: 0,
            totalPlayDelta: 0,
            totalSkipDelta: 0,
            totalListeningDuration: 0,
            playedSongCount: 0,
            newSongCount: 0,
            topSongs: [],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            topNewSongs: []
        )
    }
}

struct RecapSnapshotSyncPayload: Codable, Equatable, Identifiable {
    let id: String
    let capturedAt: Date
    let counterSignature: String
    let encodedSnapshot: Data
    let encodedRecaps: Data?
    let encodedYearlyRecaps: Data?

    init(
        id: String,
        capturedAt: Date,
        counterSignature: String,
        encodedSnapshot: Data,
        encodedRecaps: Data? = nil,
        encodedYearlyRecaps: Data? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.counterSignature = counterSignature
        self.encodedSnapshot = encodedSnapshot
        self.encodedRecaps = encodedRecaps
        self.encodedYearlyRecaps = encodedYearlyRecaps
    }
}

struct YearlyRecapMonthlyHighlight: Identifiable, Equatable {
    let month: Date
    let recap: MonthlyRecap

    var id: Date { month }
}

extension MonthlyRecap {
    static func yearly(
        for year: Int,
        months: [Date],
        monthlyRecaps: [MonthlyRecap],
        fallbackMonth: Date,
        fallbackRecap: MonthlyRecap
    ) -> MonthlyRecap {
        let calendar = Calendar.current
        guard let firstMonth = months.first else {
            return fallbackRecap
        }

        let monthStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? fallbackMonth

        var songs: [UInt64: RankedSongAggregate] = [:]
        var albums: [String: RankedGroupAggregate] = [:]
        var artists: [String: RankedGroupAggregate] = [:]
        var movement: [UInt64: MovementSongAggregate] = [:]
        var newSongIDs: [UInt64] = []

        for recap in monthlyRecaps {
            var mergedSongIDsForMonth: Set<UInt64> = []

            for song in recap.topSongs {
                songs[song.id, default: RankedSongAggregate(song: song)].merge(song)
                mergedSongIDsForMonth.insert(song.id)
            }

            for song in recap.topNewSongs {
                if !mergedSongIDsForMonth.contains(song.id) {
                    songs[song.id, default: RankedSongAggregate(song: song)].merge(song)
                    mergedSongIDsForMonth.insert(song.id)
                }
                if !newSongIDs.contains(song.id) {
                    newSongIDs.append(song.id)
                }
            }

            for group in recap.topAlbums {
                albums[group.id, default: RankedGroupAggregate(group: group)].merge(group)
            }
            for group in recap.topArtists {
                artists[group.id, default: RankedGroupAggregate(group: group)].merge(group)
            }
            for song in recap.biggestGainers {
                movement[song.id, default: MovementSongAggregate(song: song)].merge(song)
            }
        }

        let rankedSongs = songs.values
            .map(\.rankedSong)
            .sorted { $0.playDelta > $1.playDelta }

        let rankedAlbums = albums.values
            .map(\.rankedGroup)
            .sorted { $0.playDelta > $1.playDelta }

        let rankedArtists = artists.values
            .map(\.rankedGroup)
            .sorted { $0.playDelta > $1.playDelta }

        let biggestGainers = movement.values
            .map(\.movementSong)
            .sorted { $0.rankChange > $1.rankChange }

        let newSongs = newSongIDs.compactMap { id in
            songs[id]?.rankedSong
        }
        .sorted { $0.playDelta > $1.playDelta }

        return MonthlyRecap(
            monthStart: monthStart,
            generatedAt: monthlyRecaps.map(\.generatedAt).max() ?? Date(),
            lastCaptureReason: monthlyRecaps.last?.lastCaptureReason,
            trackingStart: monthlyRecaps.compactMap(\.trackingStart).min() ?? firstMonth,
            snapshotCount: monthlyRecaps.reduce(0) { $0 + $1.snapshotCount },
            totalPlayDelta: monthlyRecaps.reduce(0) { $0 + $1.totalPlayDelta },
            totalSkipDelta: monthlyRecaps.reduce(0) { $0 + $1.totalSkipDelta },
            totalListeningDuration: monthlyRecaps.reduce(0) { $0 + $1.totalListeningDuration },
            playedSongCount: songs.count,
            newSongCount: monthlyRecaps.reduce(0) { $0 + $1.newSongCount },
            topSongs: rankedSongs,
            topArtists: rankedArtists,
            topAlbums: rankedAlbums,
            biggestGainers: biggestGainers,
            topNewSongs: newSongs
        )
    }

    private struct RankedSongAggregate {
        let id: UInt64
        let title: String
        let artist: String
        let albumTitle: String
        let artwork: MPMediaItemArtwork?
        var playDelta: Int
        var skipDelta: Int
        var listeningDuration: TimeInterval

        init(song: MonthlyRecap.RankedSong) {
            id = song.id
            title = song.title
            artist = song.artist
            albumTitle = song.albumTitle
            artwork = song.artwork
            playDelta = 0
            skipDelta = 0
            listeningDuration = 0
        }

        mutating func merge(_ song: MonthlyRecap.RankedSong) {
            playDelta += song.playDelta
            skipDelta += song.skipDelta
            listeningDuration += song.listeningDuration
        }

        var rankedSong: MonthlyRecap.RankedSong {
            MonthlyRecap.RankedSong(
                id: id,
                title: title,
                artist: artist,
                albumTitle: albumTitle,
                playDelta: playDelta,
                skipDelta: skipDelta,
                listeningDuration: listeningDuration,
                artwork: artwork
            )
        }
    }

    private struct RankedGroupAggregate {
        let id: String
        let title: String
        let subtitle: String
        let artwork: MPMediaItemArtwork?
        var playDelta: Int
        var listeningDuration: TimeInterval

        init(group: MonthlyRecap.RankedGroup) {
            id = group.id
            title = group.title
            subtitle = group.subtitle
            artwork = group.artwork
            playDelta = 0
            listeningDuration = 0
        }

        mutating func merge(_ group: MonthlyRecap.RankedGroup) {
            playDelta += group.playDelta
            listeningDuration += group.listeningDuration
        }

        var rankedGroup: MonthlyRecap.RankedGroup {
            MonthlyRecap.RankedGroup(
                id: id,
                title: title,
                subtitle: subtitle,
                playDelta: playDelta,
                listeningDuration: listeningDuration,
                artwork: artwork
            )
        }
    }

    private struct MovementSongAggregate {
        let id: UInt64
        let title: String
        let artist: String
        var playDelta: Int
        var rankChange: Int
        var currentRank: Int
        var previousRank: Int?
        let artwork: MPMediaItemArtwork?

        init(song: MonthlyRecap.MovementSong) {
            id = song.id
            title = song.title
            artist = song.artist
            playDelta = 0
            rankChange = 0
            currentRank = song.currentRank
            previousRank = song.previousRank
            artwork = song.artwork
        }

        mutating func merge(_ song: MonthlyRecap.MovementSong) {
            playDelta += song.playDelta
            rankChange = max(rankChange, song.rankChange)
        }

        var movementSong: MonthlyRecap.MovementSong {
            MonthlyRecap.MovementSong(
                id: id,
                title: title,
                artist: artist,
                playDelta: playDelta,
                rankChange: rankChange,
                currentRank: currentRank,
                previousRank: previousRank,
                artwork: artwork
            )
        }
    }
}

final class MonthlyRecapSnapshotStore {
    fileprivate static let maxSyncPayloadBytes = 250_000
    fileprivate static let minSyncedSongCount = 100
    fileprivate static let maxPrioritySyncedSongCount = 120
    fileprivate static let maxSyncedRecapRankedSongCount = 250
    fileprivate static let maxSyncedRecapRankedGroupCount = 100
    fileprivate static let maxSyncedRecapMovementSongCount = 100

    fileprivate struct LibrarySnapshot: Codable {
        let capturedAt: Date
        let reason: RecapSnapshotReason?
        let appVersion: String?
        let scannedSongCount: Int?
        let deviceIdentifier: String?
        let aggregateCounters: AggregateCounters?
        let songs: [SongSnapshot]

        init(
            capturedAt: Date,
            reason: RecapSnapshotReason?,
            appVersion: String?,
            scannedSongCount: Int?,
            deviceIdentifier: String?,
            aggregateCounters: AggregateCounters? = nil,
            songs: [SongSnapshot]
        ) {
            self.capturedAt = capturedAt
            self.reason = reason
            self.appVersion = appVersion
            self.scannedSongCount = scannedSongCount
            self.deviceIdentifier = deviceIdentifier
            self.aggregateCounters = aggregateCounters
            self.songs = songs
        }
    }

    fileprivate struct SongSnapshot: Codable {
        let id: UInt64
        let title: String
        let artist: String
        let albumTitle: String
        let playCount: Int
        let skipCount: Int
        let playbackDuration: TimeInterval
        let lastPlayedDate: Date?
        let dateAdded: Date?
        let albumPersistentID: UInt64
        let artistPersistentID: UInt64
    }

    fileprivate struct AggregateCounters: Codable, Equatable {
        let playCount: Int
        let skipCount: Int
        let listeningDuration: TimeInterval
        let monthNewSongCount: Int
    }

    private struct RecapCandidate {
        let recap: MonthlyRecap
        let rankingCoverage: Double
        let sourceSnapshotCount: Int

        var hasRankingEvidence: Bool {
            recap.totalPlayDelta == 0 ||
                !recap.topSongs.isEmpty ||
                !recap.topArtists.isEmpty ||
                !recap.topAlbums.isEmpty
        }
    }

    fileprivate struct SyncedMonthlyRecap: Codable, Equatable, Identifiable {
        struct RankedSong: Codable, Equatable {
            let id: UInt64
            let title: String
            let artist: String
            let albumTitle: String
            let playDelta: Int
            let skipDelta: Int
            let listeningDuration: TimeInterval
        }

        struct RankedGroup: Codable, Equatable {
            let id: String
            let title: String
            let subtitle: String
            let playDelta: Int
            let listeningDuration: TimeInterval
        }

        struct MovementSong: Codable, Equatable {
            let id: UInt64
            let title: String
            let artist: String
            let playDelta: Int
            let rankChange: Int
            let currentRank: Int
            let previousRank: Int?
        }

        let monthStart: Date
        let generatedAt: Date
        let lastCaptureReason: RecapSnapshotReason?
        let trackingStart: Date?
        let snapshotCount: Int
        let totalPlayDelta: Int
        let totalSkipDelta: Int
        let totalListeningDuration: TimeInterval
        let playedSongCount: Int
        let newSongCount: Int
        let topSongs: [RankedSong]
        let topArtists: [RankedGroup]
        let topAlbums: [RankedGroup]
        let biggestGainers: [MovementSong]
        let topNewSongs: [RankedSong]

        var id: Date { monthStart }

        var rankedEvidenceCount: Int {
            topSongs.count + topArtists.count + topAlbums.count + biggestGainers.count + topNewSongs.count
        }

        var rankingFingerprint: String {
            let songs = topSongs.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            let artists = topArtists.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            let albums = topAlbums.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            let gainers = biggestGainers.map { "\($0.id):\($0.playDelta):\($0.rankChange)" }.joined(separator: ",")
            let newSongs = topNewSongs.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            return [songs, artists, albums, gainers, newSongs].joined(separator: "|")
        }

        var hasActivity: Bool {
            totalPlayDelta > 0 || newSongCount > 0
        }

        var hasRankingEvidence: Bool {
            totalPlayDelta == 0 || !topSongs.isEmpty || !topArtists.isEmpty || !topAlbums.isEmpty
        }

        init(recap: MonthlyRecap) {
            monthStart = recap.monthStart
            generatedAt = recap.generatedAt
            lastCaptureReason = recap.lastCaptureReason
            trackingStart = recap.trackingStart
            snapshotCount = recap.snapshotCount
            totalPlayDelta = recap.totalPlayDelta
            totalSkipDelta = recap.totalSkipDelta
            totalListeningDuration = recap.totalListeningDuration
            playedSongCount = recap.playedSongCount
            newSongCount = recap.newSongCount
            topSongs = recap.topSongs.prefix(MonthlyRecapSnapshotStore.maxSyncedRecapRankedSongCount).map {
                RankedSong(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    albumTitle: $0.albumTitle,
                    playDelta: $0.playDelta,
                    skipDelta: $0.skipDelta,
                    listeningDuration: $0.listeningDuration
                )
            }
            topArtists = recap.topArtists.prefix(MonthlyRecapSnapshotStore.maxSyncedRecapRankedGroupCount).map {
                RankedGroup(
                    id: $0.id,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    playDelta: $0.playDelta,
                    listeningDuration: $0.listeningDuration
                )
            }
            topAlbums = recap.topAlbums.prefix(MonthlyRecapSnapshotStore.maxSyncedRecapRankedGroupCount).map {
                RankedGroup(
                    id: $0.id,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    playDelta: $0.playDelta,
                    listeningDuration: $0.listeningDuration
                )
            }
            biggestGainers = recap.biggestGainers.prefix(MonthlyRecapSnapshotStore.maxSyncedRecapMovementSongCount).map {
                MovementSong(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    playDelta: $0.playDelta,
                    rankChange: $0.rankChange,
                    currentRank: $0.currentRank,
                    previousRank: $0.previousRank
                )
            }
            topNewSongs = recap.topNewSongs.prefix(MonthlyRecapSnapshotStore.maxSyncedRecapRankedSongCount).map {
                RankedSong(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    albumTitle: $0.albumTitle,
                    playDelta: $0.playDelta,
                    skipDelta: $0.skipDelta,
                    listeningDuration: $0.listeningDuration
                )
            }
        }

        func monthlyRecap(artworkLookup: ArtworkLookup) -> MonthlyRecap {
            MonthlyRecap(
                monthStart: monthStart,
                generatedAt: generatedAt,
                lastCaptureReason: lastCaptureReason,
                trackingStart: trackingStart,
                snapshotCount: snapshotCount,
                totalPlayDelta: totalPlayDelta,
                totalSkipDelta: totalSkipDelta,
                totalListeningDuration: totalListeningDuration,
                playedSongCount: playedSongCount,
                newSongCount: newSongCount,
                topSongs: topSongs.map {
                    MonthlyRecap.RankedSong(
                        id: $0.id,
                        title: $0.title,
                        artist: $0.artist,
                        albumTitle: $0.albumTitle,
                        playDelta: $0.playDelta,
                        skipDelta: $0.skipDelta,
                        listeningDuration: $0.listeningDuration,
                        artwork: artworkLookup.songs[$0.id]
                    )
                },
                topArtists: topArtists.map {
                    MonthlyRecap.RankedGroup(
                        id: $0.id,
                        title: $0.title,
                        subtitle: $0.subtitle,
                        playDelta: $0.playDelta,
                        listeningDuration: $0.listeningDuration,
                        artwork: artworkLookup.artists[UInt64($0.id) ?? 0] ?? artworkLookup.artistsByName[$0.title.normalizedArtworkKey]
                    )
                },
                topAlbums: topAlbums.map {
                    MonthlyRecap.RankedGroup(
                        id: $0.id,
                        title: $0.title,
                        subtitle: $0.subtitle,
                        playDelta: $0.playDelta,
                        listeningDuration: $0.listeningDuration,
                        artwork: artworkLookup.albums[UInt64($0.id) ?? 0] ?? artworkLookup.albumsByName[ArtworkLookup.albumKey(title: $0.title, artist: $0.subtitle)]
                    )
                },
                biggestGainers: biggestGainers.map {
                    MonthlyRecap.MovementSong(
                        id: $0.id,
                        title: $0.title,
                        artist: $0.artist,
                        playDelta: $0.playDelta,
                        rankChange: $0.rankChange,
                        currentRank: $0.currentRank,
                        previousRank: $0.previousRank,
                        artwork: artworkLookup.songs[$0.id]
                    )
                },
                topNewSongs: topNewSongs.map {
                    MonthlyRecap.RankedSong(
                        id: $0.id,
                        title: $0.title,
                        artist: $0.artist,
                        albumTitle: $0.albumTitle,
                        playDelta: $0.playDelta,
                        skipDelta: $0.skipDelta,
                        listeningDuration: $0.listeningDuration,
                        artwork: artworkLookup.songs[$0.id]
                    )
                }
            )
        }
    }

    fileprivate struct SyncedYearlyRecap: Codable, Equatable, Identifiable {
        let year: Int
        let recap: SyncedMonthlyRecap

        var id: Int { year }

        init(year: Int, recap: MonthlyRecap) {
            self.year = year
            self.recap = SyncedMonthlyRecap(recap: recap)
        }

        func monthlyRecap(artworkLookup: ArtworkLookup) -> MonthlyRecap {
            recap.monthlyRecap(artworkLookup: artworkLookup)
        }
    }

    private struct SyncedRecapSummaries: Codable, Equatable {
        let monthlyRecaps: [SyncedMonthlyRecap]
        let yearlyRecaps: [SyncedYearlyRecap]
    }

    private struct StoredSnapshots: Codable {
        var schemaVersion: Int
        var snapshots: [LibrarySnapshot]
        var syncedRecaps: [SyncedMonthlyRecap]
        var syncedYearlyRecaps: [SyncedYearlyRecap]

        init(
            schemaVersion: Int,
            snapshots: [LibrarySnapshot],
            syncedRecaps: [SyncedMonthlyRecap] = [],
            syncedYearlyRecaps: [SyncedYearlyRecap] = []
        ) {
            self.schemaVersion = schemaVersion
            self.snapshots = snapshots
            self.syncedRecaps = syncedRecaps
            self.syncedYearlyRecaps = syncedYearlyRecaps
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case snapshots
            case syncedRecaps
            case syncedYearlyRecaps
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            snapshots = try container.decode([LibrarySnapshot].self, forKey: .snapshots)
            syncedRecaps = try container.decodeIfPresent([SyncedMonthlyRecap].self, forKey: .syncedRecaps) ?? []
            syncedYearlyRecaps = try container.decodeIfPresent([SyncedYearlyRecap].self, forKey: .syncedYearlyRecaps) ?? []
        }
    }

    private struct SongDelta {
        let latest: SongSnapshot
        let playDelta: Int
        let skipDelta: Int

        var listeningDuration: TimeInterval {
            TimeInterval(playDelta) * latest.playbackDuration
        }
    }

    fileprivate struct ArtworkLookup {
        let songs: [UInt64: MPMediaItemArtwork]
        let albums: [UInt64: MPMediaItemArtwork]
        let artists: [UInt64: MPMediaItemArtwork]
        let albumsByName: [String: MPMediaItemArtwork]
        let artistsByName: [String: MPMediaItemArtwork]

        init(sourceSongs: [TopSong], sourceAlbums: [TopAlbum] = [], sourceArtists: [TopArtist] = []) {
            var songs: [UInt64: MPMediaItemArtwork] = [:]
            var albums: [UInt64: MPMediaItemArtwork] = [:]
            var artists: [UInt64: MPMediaItemArtwork] = [:]
            var albumsByName: [String: MPMediaItemArtwork] = [:]
            var artistsByName: [String: MPMediaItemArtwork] = [:]

            for song in sourceSongs {
                if let artwork = song.artwork {
                    songs[song.id] = artwork

                    if song.albumPersistentID != 0, albums[song.albumPersistentID] == nil {
                        albums[song.albumPersistentID] = artwork
                    }

                    let albumKey = Self.albumKey(title: song.albumTitle, artist: song.artist)
                    if albumsByName[albumKey] == nil {
                        albumsByName[albumKey] = artwork
                    }

                    if song.artistPersistentID != 0, artists[song.artistPersistentID] == nil {
                        artists[song.artistPersistentID] = artwork
                    }

                    let artistKey = Self.artistKey(song.artist)
                    if artistsByName[artistKey] == nil {
                        artistsByName[artistKey] = artwork
                    }
                }
            }

            for album in sourceAlbums {
                guard let artwork = album.artwork else { continue }

                if album.id != 0, albums[album.id] == nil {
                    albums[album.id] = artwork
                }

                let albumKey = Self.albumKey(title: album.title, artist: album.artist)
                if albumsByName[albumKey] == nil {
                    albumsByName[albumKey] = artwork
                }

                if album.artistPersistentID != 0, artists[album.artistPersistentID] == nil {
                    artists[album.artistPersistentID] = artwork
                }
            }

            for artist in sourceArtists {
                guard let artwork = artist.artwork else { continue }

                if artist.id != 0, artists[artist.id] == nil {
                    artists[artist.id] = artwork
                }

                let artistKey = Self.artistKey(artist.name)
                if artistsByName[artistKey] == nil {
                    artistsByName[artistKey] = artwork
                }
            }

            self.songs = songs
            self.albums = albums
            self.artists = artists
            self.albumsByName = albumsByName
            self.artistsByName = artistsByName
        }

        func artwork(for song: SongSnapshot) -> MPMediaItemArtwork? {
            songs[song.id] ?? albumArtwork(for: song)
        }

        func albumArtwork(for song: SongSnapshot) -> MPMediaItemArtwork? {
            if song.albumPersistentID != 0, let artwork = albums[song.albumPersistentID] {
                return artwork
            }
            return albumsByName[Self.albumKey(title: song.albumTitle, artist: song.artist)]
        }

        func artistArtwork(for song: SongSnapshot) -> MPMediaItemArtwork? {
            if song.artistPersistentID != 0, let artwork = artists[song.artistPersistentID] {
                return artwork
            }
            return artistsByName[Self.artistKey(song.artist)]
        }

        fileprivate static func albumKey(title: String, artist: String) -> String {
            "\(title.normalizedArtworkKey)|\(artist.normalizedArtworkKey)"
        }

        fileprivate static func artistKey(_ artist: String) -> String {
            artist.normalizedArtworkKey
        }
    }

    private let fileURL: URL
    private let calendar: Calendar
    private let deviceIdentifier: String
    private let accessQueue = DispatchQueue(label: "com.playcount.monthly-recap-snapshots")
    private let retentionMonths = 18
    private let minimumSnapshotInterval: TimeInterval = 60 * 30
    private let minimumComparableCoverageRatio = 0.9
    private let maximumListeningElapsedRatio = 1.25
    private var loadedSnapshots: StoredSnapshots?

    private static func localDeviceIdentifier() -> String {
        let key = "PlayCountRecapSnapshotDeviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let identifier = UUID().uuidString
        UserDefaults.standard.set(identifier, forKey: key)
        return identifier
    }

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        calendar: Calendar = .current,
        deviceIdentifier: String = MonthlyRecapSnapshotStore.localDeviceIdentifier()
    ) {
        self.calendar = calendar
        self.deviceIdentifier = deviceIdentifier

        let resolvedDirectoryURL: URL
        if let providedDirectoryURL = directoryURL {
            resolvedDirectoryURL = providedDirectoryURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            resolvedDirectoryURL = baseURL.appendingPathComponent("PlayCount", isDirectory: true)
        }
        try? fileManager.createDirectory(at: resolvedDirectoryURL, withIntermediateDirectories: true)
        fileURL = resolvedDirectoryURL.appendingPathComponent("monthly-recap-snapshots.json")
    }

    func record(
        songs: [TopSong],
        albums: [TopAlbum] = [],
        artists: [TopArtist] = [],
        at capturedAt: Date,
        reason: RecapSnapshotReason
    ) -> MonthlyRecap {
        accessQueue.sync {
            recordLocked(songs: songs, albums: albums, artists: artists, at: capturedAt, reason: reason)
        }
    }

    func currentMonthRecap(at date: Date = Date()) -> MonthlyRecap {
        accessQueue.sync {
            let stored = loadLocked()
            return recap(
                for: date,
                snapshots: stored.snapshots,
                syncedRecaps: stored.syncedRecaps
            )
        }
    }

    func recap(
        forMonthContaining date: Date,
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> MonthlyRecap {
        accessQueue.sync {
            let stored = loadLocked()
            return recap(
                for: date,
                snapshots: stored.snapshots,
                syncedRecaps: stored.syncedRecaps,
                sourceSongs: sourceSongs,
                sourceAlbums: sourceAlbums,
                sourceArtists: sourceArtists
            )
        }
    }

    func recaps(
        forMonthsContaining dates: [Date],
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> [MonthlyRecap] {
        accessQueue.sync {
            let stored = loadLocked()
            return dates.map {
                recap(
                    for: $0,
                    snapshots: stored.snapshots,
                    syncedRecaps: stored.syncedRecaps,
                    sourceSongs: sourceSongs,
                    sourceAlbums: sourceAlbums,
                    sourceArtists: sourceArtists
                )
            }
        }
    }

    func syncedYearlyRecap(
        for year: Int,
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> MonthlyRecap? {
        accessQueue.sync {
            let stored = loadLocked()
            let artworkLookup = ArtworkLookup(sourceSongs: sourceSongs, sourceAlbums: sourceAlbums, sourceArtists: sourceArtists)
            return stored.syncedYearlyRecaps
                .filter { $0.year == year }
                .sorted {
                    Self.isHigherPrioritySyncedRecap($0.recap, than: $1.recap)
                }
                .first?
                .monthlyRecap(artworkLookup: artworkLookup)
        }
    }

    #if DEBUG
    func debugRecordLegacySnapshot(
        songs: [TopSong],
        at capturedAt: Date,
        reason: RecapSnapshotReason,
        scannedSongCount: Int? = nil,
        aggregateSongs: [TopSong]? = nil
    ) -> MonthlyRecap {
        accessQueue.sync {
            let aggregateSourceSongs = aggregateSongs ?? songs
            var stored = loadLocked()
            let snapshot = LibrarySnapshot(
                capturedAt: capturedAt,
                reason: reason,
                appVersion: "debug-legacy",
                scannedSongCount: scannedSongCount ?? songs.count,
                deviceIdentifier: nil,
                aggregateCounters: Self.aggregateCounters(from: aggregateSourceSongs, capturedAt: capturedAt, calendar: calendar),
                songs: songs.map(SongSnapshot.init(song:))
            )

            if shouldAppend(snapshot, after: stored.snapshots.last) {
                stored.snapshots.append(snapshot)
                stored.snapshots = retainedCanonicalSnapshots(from: stored.snapshots, now: capturedAt)
                _ = updateSyncedRecaps(in: &stored, snapshots: stored.snapshots)
                saveLocked(stored)
            }

            return recap(
                for: capturedAt,
                snapshots: stored.snapshots,
                syncedRecaps: stored.syncedRecaps,
                sourceSongs: songs
            )
        }
    }
    #endif

    func availableMonthStarts(through date: Date = Date()) -> [Date] {
        accessQueue.sync {
            let ordered = loadLocked().snapshots.sorted { $0.capturedAt < $1.capturedAt }
            let currentMonth = calendar.startOfMonth(containing: date)

            guard let firstSnapshot = ordered.first else {
                return [currentMonth]
            }

            let firstMonth = calendar.startOfMonth(containing: firstSnapshot.capturedAt)
            let monthCount = max(0, calendar.dateComponents([.month], from: firstMonth, to: currentMonth).month ?? 0)

            return (0...monthCount).compactMap {
                calendar.date(byAdding: .month, value: $0, to: firstMonth)
            }
        }
    }

    func syncPayloads() -> [RecapSnapshotSyncPayload] {
        accessQueue.sync {
            var stored = loadLocked()
            var didChange = backfillAggregateCounters(in: &stored)
            if compactRetainedCanonicalSnapshots(in: &stored, now: Date()) {
                didChange = true
            }
            if updateSyncedRecaps(in: &stored, snapshots: stored.snapshots) {
                didChange = true
            }
            if didChange {
                saveLocked(stored)
            }
            let encodedRecaps = Self.encodedSyncedRecaps(stored.syncedRecaps)
            let encodedYearlyRecaps = Self.encodedSyncedYearlyRecaps(stored.syncedYearlyRecaps)
            let prioritySongIDs = syncPrioritySongIDsBySnapshotKey(
                for: stored.snapshots,
                currentDeviceIdentifier: deviceIdentifier
            )
            return stored.snapshots.sortedForSyncPayloads().compactMap { snapshot in
                snapshot.syncPayload(
                    prioritySongIDs: prioritySongIDs[snapshot.syncPayloadKey] ?? [],
                    encodedRecaps: encodedRecaps,
                    encodedYearlyRecaps: encodedYearlyRecaps
                )
            }
            .uniquedByID()
        }
    }

    func localSyncPayloads() -> [RecapSnapshotSyncPayload] {
        accessQueue.sync {
            var stored = loadLocked()
            var didChange = backfillAggregateCounters(in: &stored)
            if compactRetainedCanonicalSnapshots(in: &stored, now: Date()) {
                didChange = true
            }
            if updateSyncedRecaps(in: &stored, snapshots: stored.snapshots) {
                didChange = true
            }
            if didChange {
                saveLocked(stored)
            }
            let localSnapshots = canonicalSnapshots(stored.snapshots.filter {
                $0.belongsToLocalDevice(currentDeviceIdentifier: deviceIdentifier)
            })
            let prioritySongIDs = syncPrioritySongIDsBySnapshotKey(
                for: localSnapshots,
                currentDeviceIdentifier: deviceIdentifier
            )
            let encodedRecaps = Self.encodedSyncedRecaps(stored.syncedRecaps)
            let encodedYearlyRecaps = Self.encodedSyncedYearlyRecaps(stored.syncedYearlyRecaps)
            return localSnapshots.sortedForSyncPayloads().compactMap { snapshot in
                snapshot.syncPayload(
                    prioritySongIDs: prioritySongIDs[snapshot.syncPayloadKey] ?? [],
                    encodedRecaps: encodedRecaps,
                    encodedYearlyRecaps: encodedYearlyRecaps
                )
            }
            .uniquedByID()
        }
    }

    @discardableResult
    func mergeSyncPayloads(_ payloads: [RecapSnapshotSyncPayload], now: Date = Date()) -> Bool {
        guard !payloads.isEmpty else { return false }

        return accessQueue.sync {
            var stored = loadLocked()
            var snapshotsByID: [String: LibrarySnapshot] = [:]
            for snapshot in stored.snapshots {
                snapshotsByID[snapshot.syncIdentifier] = snapshot
            }
            let incomingSyncedRecaps = payloads.flatMap(Self.syncedRecaps)
            let incomingSyncedYearlyRecaps = payloads.flatMap(Self.syncedYearlyRecaps)
            var didChange = false

            for payload in payloads {
                guard let snapshot = LibrarySnapshot(syncPayload: payload) else { continue }
                if snapshotsByID[snapshot.syncIdentifier] == nil {
                    snapshotsByID[snapshot.syncIdentifier] = snapshot
                    didChange = true
                }
            }

            let mergedSyncedRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps + incomingSyncedRecaps)
            if mergedSyncedRecaps != stored.syncedRecaps {
                stored.syncedRecaps = mergedSyncedRecaps
                didChange = true
            }

            let mergedSyncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(stored.syncedYearlyRecaps + incomingSyncedYearlyRecaps)
            if mergedSyncedYearlyRecaps != stored.syncedYearlyRecaps {
                stored.syncedYearlyRecaps = mergedSyncedYearlyRecaps
                didChange = true
            }

            guard didChange else { return false }

            stored.snapshots = retainedCanonicalSnapshots(
                from: Array(snapshotsByID.values).sortedForSyncPayloads(),
                now: now
            )
            _ = updateSyncedRecaps(in: &stored, snapshots: stored.snapshots)
            saveLocked(stored)
            return true
        }
    }

    func debugSummary(at date: Date = Date()) -> String {
        accessQueue.sync {
            let stored = loadLocked()
            let ordered = stored.snapshots.sorted { $0.capturedAt < $1.capturedAt }
            let recap = recap(for: date, snapshots: ordered, syncedRecaps: stored.syncedRecaps)
            let monthStart = calendar.startOfMonth(containing: date)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? date
            let inMonth = ordered.filter { $0.capturedAt >= monthStart && $0.capturedAt < monthEnd }
            let latest = ordered.last(where: { $0.capturedAt < monthEnd })
            let baseline = latest.map {
                baselineSnapshot(for: $0, inMonth: inMonth, ordered: ordered, monthStart: monthStart)
            }
            let lines = ordered.suffix(8).map { snapshot in
                let totalPlays = snapshot.songs.reduce(0) { $0 + $1.playCount }
                let totalSkips = snapshot.songs.reduce(0) { $0 + $1.skipCount }
                let reason = snapshot.reason?.rawValue ?? "unknown"
                return "\(snapshot.capturedAt.formatted(date: .numeric, time: .standard)) | \(reason) | songs=\(snapshot.songs.count) | plays=\(totalPlays) | skips=\(totalSkips)"
            }

            return """
            Snapshot file: \(fileURL.path)
            Snapshots stored: \(ordered.count)
            Month snapshots: \(inMonth.count)
            Baseline snapshot: \(baseline?.capturedAt.formatted(date: .numeric, time: .standard) ?? "none")
            Latest snapshot: \(latest?.capturedAt.formatted(date: .numeric, time: .standard) ?? "none")
            Current recap plays: \(recap.totalPlayDelta)
            Current recap skips: \(recap.totalSkipDelta)
            Current recap songs: \(recap.topSongs.map { "\($0.title):+\($0.playDelta)" }.joined(separator: ", "))
            Biggest gainers: \(recap.biggestGainers.map { "\($0.title):+\($0.rankChange)" }.joined(separator: ", "))
            Top new songs: \(recap.topNewSongs.map { "\($0.title):+\($0.playDelta)" }.joined(separator: ", "))

            Recent snapshots:
            \(lines.joined(separator: "\n"))
            """
        }
    }

    private func recordLocked(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist],
        at capturedAt: Date,
        reason: RecapSnapshotReason
    ) -> MonthlyRecap {
        var stored = loadLocked()
        let snapshot = LibrarySnapshot(
            capturedAt: capturedAt,
            reason: reason,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            scannedSongCount: songs.count,
            deviceIdentifier: deviceIdentifier,
            aggregateCounters: Self.aggregateCounters(from: songs, capturedAt: capturedAt, calendar: calendar),
            songs: songs.map(SongSnapshot.init(song:))
        )

        if shouldAppend(snapshot, after: stored.snapshots.last) {
            stored.snapshots.append(snapshot)
            stored.snapshots = retainedCanonicalSnapshots(from: stored.snapshots, now: capturedAt)
            _ = updateSyncedRecaps(in: &stored, snapshots: stored.snapshots)
            saveLocked(stored)
        }

        return recap(
            for: capturedAt,
            snapshots: stored.snapshots,
            syncedRecaps: stored.syncedRecaps,
            sourceSongs: songs,
            sourceAlbums: albums,
            sourceArtists: artists
        )
    }

    private func shouldAppend(_ snapshot: LibrarySnapshot, after previous: LibrarySnapshot?) -> Bool {
        guard let previous else { return true }

        if snapshot.capturedAt.timeIntervalSince(previous.capturedAt) >= minimumSnapshotInterval {
            return true
        }

        return snapshot.counterSignature != previous.counterSignature
    }

    private func retainedSnapshots(from snapshots: [LibrarySnapshot], now: Date) -> [LibrarySnapshot] {
        guard let cutoff = calendar.date(byAdding: .month, value: -retentionMonths, to: now) else {
            return snapshots
        }
        return snapshots.filter { $0.capturedAt >= cutoff }
    }

    private func retainedCanonicalSnapshots(from snapshots: [LibrarySnapshot], now: Date) -> [LibrarySnapshot] {
        canonicalSnapshots(retainedSnapshots(from: snapshots, now: now))
    }

    private func compactRetainedCanonicalSnapshots(in stored: inout StoredSnapshots, now: Date) -> Bool {
        let snapshots = retainedCanonicalSnapshots(from: stored.snapshots, now: now)
        let existingIDs = stored.snapshots.map(\.syncIdentifier)
        let compactedIDs = snapshots.map(\.syncIdentifier)
        guard existingIDs != compactedIDs else { return false }

        stored.snapshots = snapshots
        return true
    }

    private func updateSyncedRecaps(in stored: inout StoredSnapshots, snapshots: [LibrarySnapshot]) -> Bool {
        let generatedRecaps = syncedRecaps(from: snapshots)
        let generatedYearlyRecaps = syncedYearlyRecaps(from: snapshots)
        let mergedRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps + generatedRecaps)
        let mergedYearlyRecaps = Self.mergedSyncedYearlyRecaps(stored.syncedYearlyRecaps + generatedYearlyRecaps)

        var didChange = false
        if mergedRecaps != stored.syncedRecaps {
            stored.syncedRecaps = mergedRecaps
            didChange = true
        }
        if mergedYearlyRecaps != stored.syncedYearlyRecaps {
            stored.syncedYearlyRecaps = mergedYearlyRecaps
            didChange = true
        }
        return didChange
    }

    private func syncedRecaps(from snapshots: [LibrarySnapshot]) -> [SyncedMonthlyRecap] {
        fullMonthlyRecaps(from: snapshots).map(SyncedMonthlyRecap.init(recap:))
    }

    private func fullMonthlyRecaps(from snapshots: [LibrarySnapshot]) -> [MonthlyRecap] {
        let monthStarts = Set(snapshots.map { calendar.startOfMonth(containing: $0.capturedAt) })
        return monthStarts.map { monthStart in
            snapshotRecap(for: monthStart, snapshots: snapshots)
        }
    }

    private func syncedYearlyRecaps(from snapshots: [LibrarySnapshot]) -> [SyncedYearlyRecap] {
        let monthlyRecapsByYear = Dictionary(grouping: fullMonthlyRecaps(from: snapshots)) {
            calendar.component(.year, from: $0.monthStart)
        }

        return monthlyRecapsByYear.map { year, recaps in
            let months = recaps.map(\.monthStart).sorted()
            let fallbackMonth = months.first ?? calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
            let yearlyRecap = MonthlyRecap.yearly(
                for: year,
                months: months,
                monthlyRecaps: recaps,
                fallbackMonth: fallbackMonth,
                fallbackRecap: .empty(for: fallbackMonth, calendar: calendar)
            )
            return SyncedYearlyRecap(year: year, recap: yearlyRecap)
        }
    }

    private static func encodedSyncedRecaps(_ recaps: [SyncedMonthlyRecap]) -> Data? {
        guard !recaps.isEmpty else { return nil }
        return try? JSONEncoder.playCount.encode(recaps)
    }

    private static func encodedSyncedYearlyRecaps(_ recaps: [SyncedYearlyRecap]) -> Data? {
        guard !recaps.isEmpty else { return nil }
        return try? JSONEncoder.playCount.encode(recaps)
    }

    private static func syncedRecaps(from payload: RecapSnapshotSyncPayload) -> [SyncedMonthlyRecap] {
        guard let encodedRecaps = payload.encodedRecaps else {
            return []
        }
        if let summaries = try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: encodedRecaps) {
            return summaries.monthlyRecaps
        }
        return (try? JSONDecoder.playCount.decode([SyncedMonthlyRecap].self, from: encodedRecaps)) ?? []
    }

    private static func syncedYearlyRecaps(from payload: RecapSnapshotSyncPayload) -> [SyncedYearlyRecap] {
        if let encodedYearlyRecaps = payload.encodedYearlyRecaps,
           let recaps = try? JSONDecoder.playCount.decode([SyncedYearlyRecap].self, from: encodedYearlyRecaps) {
            return recaps
        }

        guard let encodedRecaps = payload.encodedRecaps,
              let summaries = try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: encodedRecaps) else {
            return []
        }
        return summaries.yearlyRecaps
    }

    private static func mergedSyncedRecaps(_ recaps: [SyncedMonthlyRecap]) -> [SyncedMonthlyRecap] {
        var recapsByMonth: [Date: SyncedMonthlyRecap] = [:]
        for recap in recaps {
            guard let existing = recapsByMonth[recap.monthStart] else {
                recapsByMonth[recap.monthStart] = recap
                continue
            }

            if isHigherPrioritySyncedRecap(recap, than: existing) {
                recapsByMonth[recap.monthStart] = recap
            }
        }

        return recapsByMonth.values.sorted {
            if $0.monthStart != $1.monthStart {
                return $0.monthStart < $1.monthStart
            }
            return $0.generatedAt < $1.generatedAt
        }
    }

    private static func mergedSyncedYearlyRecaps(_ recaps: [SyncedYearlyRecap]) -> [SyncedYearlyRecap] {
        var recapsByYear: [Int: SyncedYearlyRecap] = [:]
        for recap in recaps {
            guard let existing = recapsByYear[recap.year] else {
                recapsByYear[recap.year] = recap
                continue
            }

            if isHigherPrioritySyncedRecap(recap.recap, than: existing.recap) {
                recapsByYear[recap.year] = recap
            }
        }

        return recapsByYear.values.sorted {
            if $0.year != $1.year {
                return $0.year < $1.year
            }
            return $0.recap.generatedAt < $1.recap.generatedAt
        }
    }

    private static func isHigherPrioritySyncedRecap(_ lhs: SyncedMonthlyRecap, than rhs: SyncedMonthlyRecap) -> Bool {
        if lhs.hasActivity != rhs.hasActivity {
            return lhs.hasActivity
        }

        if lhs.hasRankingEvidence != rhs.hasRankingEvidence {
            return lhs.hasRankingEvidence
        }

        if lhs.totalPlayDelta != rhs.totalPlayDelta {
            return lhs.totalPlayDelta > rhs.totalPlayDelta
        }

        if lhs.totalListeningDuration != rhs.totalListeningDuration {
            return lhs.totalListeningDuration > rhs.totalListeningDuration
        }

        if lhs.newSongCount != rhs.newSongCount {
            return lhs.newSongCount > rhs.newSongCount
        }

        if lhs.rankedEvidenceCount != rhs.rankedEvidenceCount {
            return lhs.rankedEvidenceCount > rhs.rankedEvidenceCount
        }

        if lhs.snapshotCount != rhs.snapshotCount {
            return lhs.snapshotCount > rhs.snapshotCount
        }

        if lhs.generatedAt != rhs.generatedAt {
            return lhs.generatedAt < rhs.generatedAt
        }

        return lhs.rankingFingerprint < rhs.rankingFingerprint
    }

    private static func aggregateCounters(
        from songs: [TopSong],
        capturedAt: Date,
        calendar: Calendar
    ) -> AggregateCounters {
        let monthStart = calendar.startOfMonth(containing: capturedAt)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? capturedAt
        return AggregateCounters(
            playCount: songs.reduce(0) { $0 + $1.playCount },
            skipCount: songs.reduce(0) { $0 + $1.skipCount },
            listeningDuration: songs.reduce(0) { $0 + (TimeInterval($1.playCount) * $1.playbackDuration) },
            monthNewSongCount: songs.filter {
                guard let dateAdded = $0.dateAdded else { return false }
                return dateAdded >= monthStart && dateAdded < monthEnd
            }.count
        )
    }

    private static func aggregateCounters(
        from songs: [SongSnapshot],
        capturedAt: Date,
        calendar: Calendar
    ) -> AggregateCounters {
        let monthStart = calendar.startOfMonth(containing: capturedAt)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? capturedAt
        return AggregateCounters(
            playCount: songs.reduce(0) { $0 + $1.playCount },
            skipCount: songs.reduce(0) { $0 + $1.skipCount },
            listeningDuration: songs.reduce(0) { $0 + (TimeInterval($1.playCount) * $1.playbackDuration) },
            monthNewSongCount: songs.filter {
                guard let dateAdded = $0.dateAdded else { return false }
                return dateAdded >= monthStart && dateAdded < monthEnd
            }.count
        )
    }

    private func backfillAggregateCounters(in stored: inout StoredSnapshots) -> Bool {
        var didChange = false
        stored.snapshots = stored.snapshots.map { snapshot in
            guard snapshot.aggregateCounters == nil else { return snapshot }
            didChange = true
            return LibrarySnapshot(
                capturedAt: snapshot.capturedAt,
                reason: snapshot.reason,
                appVersion: snapshot.appVersion,
                scannedSongCount: snapshot.scannedSongCount,
                deviceIdentifier: snapshot.deviceIdentifier,
                aggregateCounters: Self.aggregateCounters(
                    from: snapshot.songs,
                    capturedAt: snapshot.capturedAt,
                    calendar: calendar
                ),
                songs: snapshot.songs
            )
        }
        return didChange
    }

    private func syncPrioritySongIDsBySnapshotKey(
        for snapshots: [LibrarySnapshot],
        currentDeviceIdentifier: String
    ) -> [String: Set<UInt64>] {
        var priorityIDsBySnapshotKey: [String: Set<UInt64>] = [:]
        let streams = Dictionary(grouping: snapshots.sorted { $0.capturedAt < $1.capturedAt }) {
            $0.logicalDeviceKey(fallbackDeviceIdentifier: currentDeviceIdentifier)
        }.mapValues(canonicalSnapshots)

        for streamSnapshots in streams.values {
            let snapshotsByMonth = Dictionary(grouping: streamSnapshots) {
                calendar.startOfMonth(containing: $0.capturedAt)
            }

            for monthSnapshots in snapshotsByMonth.values {
                let orderedMonthSnapshots = monthSnapshots.sorted { $0.capturedAt < $1.capturedAt }
                guard let baseline = orderedMonthSnapshots.first else { continue }
                let monthStart = calendar.startOfMonth(containing: baseline.capturedAt)
                let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? baseline.capturedAt
                let baselineSongsByID = Dictionary(uniqueKeysWithValues: baseline.songs.map { ($0.id, $0) })
                var changedSongScores: [UInt64: (playDelta: Int, listeningDuration: TimeInterval)] = [:]

                for snapshot in orderedMonthSnapshots.dropFirst() {
                    for song in snapshot.songs {
                        let playDelta: Int
                        if let baselineSong = baselineSongsByID[song.id] {
                            guard song.playCount != baselineSong.playCount || song.skipCount != baselineSong.skipCount else {
                                continue
                            }
                            playDelta = max(0, song.playCount - baselineSong.playCount)
                        } else {
                            guard let dateAdded = song.dateAdded,
                                  dateAdded >= baseline.capturedAt,
                                  dateAdded >= monthStart,
                                  dateAdded < monthEnd else {
                                continue
                            }
                            playDelta = max(0, song.playCount)
                        }

                        let listeningDuration = TimeInterval(playDelta) * song.playbackDuration
                        if let existing = changedSongScores[song.id] {
                            if playDelta > existing.playDelta ||
                                (playDelta == existing.playDelta && listeningDuration > existing.listeningDuration) {
                                changedSongScores[song.id] = (playDelta, listeningDuration)
                            }
                        } else {
                            changedSongScores[song.id] = (playDelta, listeningDuration)
                        }
                    }
                }

                let changedSongIDs = Set(
                    changedSongScores
                        .sorted {
                            if $0.value.playDelta != $1.value.playDelta {
                                return $0.value.playDelta > $1.value.playDelta
                            }
                            return $0.value.listeningDuration > $1.value.listeningDuration
                        }
                        .prefix(Self.maxPrioritySyncedSongCount)
                        .map(\.key)
                )
                guard !changedSongIDs.isEmpty else { continue }
                for snapshot in orderedMonthSnapshots {
                    priorityIDsBySnapshotKey[snapshot.syncPayloadKey, default: []].formUnion(changedSongIDs)
                }
            }
        }

        return priorityIDsBySnapshotKey
    }

    private func recap(
        for date: Date,
        snapshots: [LibrarySnapshot],
        syncedRecaps: [SyncedMonthlyRecap] = [],
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> MonthlyRecap {
        let artworkLookup = ArtworkLookup(sourceSongs: sourceSongs, sourceAlbums: sourceAlbums, sourceArtists: sourceArtists)
        let snapshotRecap = snapshotRecap(
            for: date,
            snapshots: snapshots,
            sourceSongs: sourceSongs,
            sourceAlbums: sourceAlbums,
            sourceArtists: sourceArtists
        )
        let monthStart = calendar.startOfMonth(containing: date)
        guard let syncedRecap = syncedRecaps
            .filter({ $0.monthStart == monthStart })
            .sorted(by: Self.isHigherPrioritySyncedRecap)
            .first?
            .monthlyRecap(artworkLookup: artworkLookup) else {
            return snapshotRecap
        }

        if isHigherPriorityDisplayRecap(syncedRecap, than: snapshotRecap) {
            return syncedRecap
        }

        return snapshotRecap
    }

    private func snapshotRecap(
        for date: Date,
        snapshots: [LibrarySnapshot],
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> MonthlyRecap {
        let ordered = snapshots.sorted { $0.capturedAt < $1.capturedAt }
        let deviceStreams = recapCandidateStreams(from: ordered)

        guard deviceStreams.count > 1 else {
            return recapCandidateForDeviceStream(
                for: date,
                snapshots: deviceStreams.first ?? ordered,
                sourceSongs: sourceSongs,
                sourceAlbums: sourceAlbums,
                sourceArtists: sourceArtists
            ).recap
        }

        return deviceStreams
            .map {
                recapCandidateForDeviceStream(
                    for: date,
                    snapshots: $0.sorted { $0.capturedAt < $1.capturedAt },
                    sourceSongs: sourceSongs,
                    sourceAlbums: sourceAlbums,
                    sourceArtists: sourceArtists
                )
            }
            .sorted(by: isHigherPriorityCandidate)
            .first?.recap ?? .empty(for: date, calendar: calendar)
    }

    private func recapCandidateStreams(from ordered: [LibrarySnapshot]) -> [[LibrarySnapshot]] {
        let deviceIdentifiers = Set(ordered.compactMap(\.deviceIdentifier))
        guard !deviceIdentifiers.isEmpty else {
            return ordered.isEmpty ? [] : [ordered]
        }

        return deviceIdentifiers.map { deviceIdentifier in
            canonicalSnapshots(ordered.filter {
                $0.deviceIdentifier == nil || $0.deviceIdentifier == deviceIdentifier
            })
        }
        .filter { !$0.isEmpty }
        .sorted {
            if $0.count != $1.count {
                return $0.count > $1.count
            }

            return ($0.last?.capturedAt ?? .distantPast) > ($1.last?.capturedAt ?? .distantPast)
        }
    }

    private func canonicalSnapshots(_ snapshots: [LibrarySnapshot]) -> [LibrarySnapshot] {
        var canonical: [LibrarySnapshot] = []
        for snapshot in snapshots {
            guard let existingIndex = canonical.firstIndex(where: { snapshot.isDuplicateRecapMoment(of: $0) }) else {
                canonical.append(snapshot)
                continue
            }

            let existing = canonical[existingIndex]
            if snapshot.isRicherRecapSource(than: existing) {
                canonical[existingIndex] = snapshot
            }
        }

        return canonical.sortedForSyncPayloads()
    }

    private func recapCandidateForDeviceStream(
        for date: Date,
        snapshots ordered: [LibrarySnapshot],
        sourceSongs: [TopSong],
        sourceAlbums: [TopAlbum],
        sourceArtists: [TopArtist]
    ) -> RecapCandidate {
        let monthStart = calendar.startOfMonth(containing: date)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? date

        guard let latest = ordered.last(where: { $0.capturedAt < monthEnd }) else {
            return RecapCandidate(
                recap: .empty(for: date, calendar: calendar),
                rankingCoverage: 0,
                sourceSnapshotCount: 0
            )
        }

        let inMonth = ordered.filter { $0.capturedAt >= monthStart && $0.capturedAt < monthEnd }
        let baseline = baselineSnapshot(for: latest, inMonth: inMonth, ordered: ordered, monthStart: monthStart)
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.songs.map { ($0.id, $0) })
        let artworkLookup = ArtworkLookup(sourceSongs: sourceSongs, sourceAlbums: sourceAlbums, sourceArtists: sourceArtists)
        let aggregateDeltas = aggregateDeltas(latest: latest, baseline: baseline)

        let deltas = latest.songs.compactMap { song -> SongDelta? in
            let baselineSong = baselineByID[song.id]
            let playDelta = playDelta(for: song, baseline: baselineSong, baselineDate: baseline.capturedAt)
            let skipDelta = max(0, song.skipCount - (baselineSong?.skipCount ?? song.skipCount))

            guard playDelta > 0 || skipDelta > 0 else { return nil }
            return SongDelta(latest: song, playDelta: playDelta, skipDelta: skipDelta)
        }

        let playDeltas = rankingDeltas(
            from: deltas.filter { $0.playDelta > 0 },
            baselineByID: baselineByID,
            monthStart: monthStart,
            monthEnd: monthEnd,
            aggregatePlayDelta: aggregateDeltas?.playDelta
        )

        let topSongs = playDeltas
            .sorted(by: compareDeltas)
            .map { rankedSong(from: $0, artworkLookup: artworkLookup) }

        let topArtists = groupedDeltas(
            playDeltas,
            id: artistGroupID,
            title: { $0.latest.artist },
            subtitle: { _ in "Artist" },
            artwork: { artworkLookup.artistArtwork(for: $0.latest) }
        )

        let topAlbums = groupedDeltas(
            playDeltas,
            id: albumGroupID,
            title: { $0.latest.albumTitle },
            subtitle: { $0.latest.artist },
            artwork: { artworkLookup.albumArtwork(for: $0.latest) }
        )

        let biggestGainers = movementSongs(
            from: playDeltas,
            baseline: baseline,
            latest: latest,
            artworkLookup: artworkLookup
        )

        let topNewSongs = playDeltas
            .filter { baselineByID[$0.latest.id] == nil }
            .sorted(by: compareDeltas)
            .map { rankedSong(from: $0, artworkLookup: artworkLookup) }

        let newSongCount = latest.songs.filter { song in
            guard let dateAdded = song.dateAdded else { return false }
            return dateAdded >= monthStart && dateAdded < monthEnd
        }.count
        let totalListeningDuration = aggregateDeltas?.listeningDuration ?? deltas.reduce(0) { $0 + $1.listeningDuration }
        let songLevelPlayDelta = playDeltas.reduce(0) { $0 + $1.playDelta }
        let expectedPlayDelta = aggregateDeltas?.playDelta ?? songLevelPlayDelta
        let rankingCoverage = expectedPlayDelta > 0
            ? min(1, Double(songLevelPlayDelta) / Double(expectedPlayDelta))
            : 1

        guard isPlausibleListeningDuration(totalListeningDuration, monthStart: monthStart, baseline: baseline, latest: latest) else {
            return RecapCandidate(
                recap: .empty(for: date, calendar: calendar),
                rankingCoverage: 0,
                sourceSnapshotCount: 0
            )
        }

        return RecapCandidate(
            recap: MonthlyRecap(
                monthStart: monthStart,
                generatedAt: latest.capturedAt,
                lastCaptureReason: latest.reason,
                trackingStart: ordered.first?.capturedAt,
                snapshotCount: inMonth.count,
                totalPlayDelta: aggregateDeltas?.playDelta ?? deltas.reduce(0) { $0 + $1.playDelta },
                totalSkipDelta: aggregateDeltas?.skipDelta ?? deltas.reduce(0) { $0 + $1.skipDelta },
                totalListeningDuration: totalListeningDuration,
                playedSongCount: playDeltas.count,
                newSongCount: latest.aggregateCounters?.monthNewSongCount ?? newSongCount,
                topSongs: topSongs,
                topArtists: topArtists,
                topAlbums: topAlbums,
                biggestGainers: biggestGainers,
                topNewSongs: topNewSongs
            ),
            rankingCoverage: rankingCoverage,
            sourceSnapshotCount: inMonth.count
        )
    }

    private func aggregateDeltas(latest: LibrarySnapshot, baseline: LibrarySnapshot) -> (playDelta: Int, skipDelta: Int, listeningDuration: TimeInterval)? {
        guard latest.isSameDevice(as: baseline),
              hasComparableCoverage(baseline, latest: latest),
              let latestCounters = latest.aggregateCounters,
              let baselineCounters = baseline.aggregateCounters else {
            return nil
        }

        return (
            playDelta: max(0, latestCounters.playCount - baselineCounters.playCount),
            skipDelta: max(0, latestCounters.skipCount - baselineCounters.skipCount),
            listeningDuration: max(0, latestCounters.listeningDuration - baselineCounters.listeningDuration)
        )
    }

    private func rankingDeltas(
        from deltas: [SongDelta],
        baselineByID: [UInt64: SongSnapshot],
        monthStart: Date,
        monthEnd: Date,
        aggregatePlayDelta: Int?
    ) -> [SongDelta] {
        guard let aggregatePlayDelta, aggregatePlayDelta > 0 else {
            return deltas
        }

        let existingSongPlayDelta = deltas.reduce(0) { total, delta in
            baselineByID[delta.latest.id] == nil ? total : total + delta.playDelta
        }
        guard existingSongPlayDelta > aggregatePlayDelta * 2 else {
            return deltas
        }

        return deltas.filter { delta in
            guard baselineByID[delta.latest.id] == nil,
                  let dateAdded = delta.latest.dateAdded else {
                return false
            }
            return dateAdded >= monthStart && dateAdded < monthEnd
        }
    }

    private func isHigherPriorityCandidate(_ lhs: RecapCandidate, than rhs: RecapCandidate) -> Bool {
        let lhsRecap = lhs.recap
        let rhsRecap = rhs.recap

        if lhsRecap.hasActivity != rhsRecap.hasActivity {
            return lhsRecap.hasActivity
        }

        let lhsHasRankingEvidence = lhs.hasRankingEvidence
        let rhsHasRankingEvidence = rhs.hasRankingEvidence
        if lhsHasRankingEvidence != rhsHasRankingEvidence {
            return lhsHasRankingEvidence
        }

        if lhsRecap.totalPlayDelta != rhsRecap.totalPlayDelta {
            return lhsRecap.totalPlayDelta > rhsRecap.totalPlayDelta
        }

        if lhsRecap.totalListeningDuration != rhsRecap.totalListeningDuration {
            return lhsRecap.totalListeningDuration > rhsRecap.totalListeningDuration
        }

        if abs(lhs.rankingCoverage - rhs.rankingCoverage) >= 0.25 {
            return lhs.rankingCoverage > rhs.rankingCoverage
        }

        if lhs.sourceSnapshotCount != rhs.sourceSnapshotCount {
            return lhs.sourceSnapshotCount > rhs.sourceSnapshotCount
        }

        return isHigherPriorityRecap(lhsRecap, than: rhsRecap)
    }

    private func isHigherPriorityDisplayRecap(_ lhs: MonthlyRecap, than rhs: MonthlyRecap) -> Bool {
        if lhs.hasActivity != rhs.hasActivity {
            return lhs.hasActivity
        }

        let lhsHasRankingEvidence = lhs.totalPlayDelta == 0 || !lhs.topSongs.isEmpty || !lhs.topArtists.isEmpty || !lhs.topAlbums.isEmpty
        let rhsHasRankingEvidence = rhs.totalPlayDelta == 0 || !rhs.topSongs.isEmpty || !rhs.topArtists.isEmpty || !rhs.topAlbums.isEmpty
        if lhsHasRankingEvidence != rhsHasRankingEvidence {
            return lhsHasRankingEvidence
        }

        if lhs.totalPlayDelta != rhs.totalPlayDelta {
            return lhs.totalPlayDelta > rhs.totalPlayDelta
        }

        if lhs.totalListeningDuration != rhs.totalListeningDuration {
            return lhs.totalListeningDuration > rhs.totalListeningDuration
        }

        if lhs.newSongCount != rhs.newSongCount {
            return lhs.newSongCount > rhs.newSongCount
        }

        let lhsEvidenceCount = lhs.topSongs.count + lhs.topArtists.count + lhs.topAlbums.count + lhs.biggestGainers.count + lhs.topNewSongs.count
        let rhsEvidenceCount = rhs.topSongs.count + rhs.topArtists.count + rhs.topAlbums.count + rhs.biggestGainers.count + rhs.topNewSongs.count
        if lhsEvidenceCount != rhsEvidenceCount {
            return lhsEvidenceCount > rhsEvidenceCount
        }

        if lhs.snapshotCount != rhs.snapshotCount {
            return lhs.snapshotCount > rhs.snapshotCount
        }

        return true
    }

    private func isHigherPriorityRecap(_ lhs: MonthlyRecap, than rhs: MonthlyRecap) -> Bool {
        if lhs.hasActivity != rhs.hasActivity {
            return lhs.hasActivity
        }

        if lhs.trackingStart != rhs.trackingStart {
            switch (lhs.trackingStart, rhs.trackingStart) {
            case let (lhsStart?, rhsStart?):
                return lhsStart < rhsStart
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
        }

        if lhs.snapshotCount != rhs.snapshotCount {
            return lhs.snapshotCount > rhs.snapshotCount
        }

        if lhs.totalListeningDuration != rhs.totalListeningDuration {
            return lhs.totalListeningDuration > rhs.totalListeningDuration
        }

        if lhs.totalPlayDelta != rhs.totalPlayDelta {
            return lhs.totalPlayDelta > rhs.totalPlayDelta
        }

        return lhs.generatedAt > rhs.generatedAt
    }

    private func rankedSong(
        from delta: SongDelta,
        artworkLookup: ArtworkLookup
    ) -> MonthlyRecap.RankedSong {
        MonthlyRecap.RankedSong(
            id: delta.latest.id,
            title: delta.latest.title,
            artist: delta.latest.artist,
            albumTitle: delta.latest.albumTitle,
            playDelta: delta.playDelta,
            skipDelta: delta.skipDelta,
            listeningDuration: delta.listeningDuration,
            artwork: artworkLookup.artwork(for: delta.latest)
        )
    }

    private func baselineSnapshot(
        for latest: LibrarySnapshot,
        inMonth: [LibrarySnapshot],
        ordered: [LibrarySnapshot],
        monthStart: Date
    ) -> LibrarySnapshot {
        let earlierInMonth = inMonth.filter { $0.capturedAt < latest.capturedAt }

        if let beforeMonth = ordered.last(where: {
            $0.capturedAt < monthStart &&
                $0.isSameDevice(as: latest) &&
                hasComparableCoverage($0, latest: latest)
        }) {
            return beforeMonth
        }

        if let firstDifferent = earlierInMonth.first(where: {
            $0.isSameDevice(as: latest) &&
                hasComparableCoverage($0, latest: latest) &&
                $0.counterSignature != latest.counterSignature
        }) {
            return firstDifferent
        }

        return earlierInMonth.first(where: { $0.isSameDevice(as: latest) && hasComparableCoverage($0, latest: latest) })
            ?? inMonth.first(where: { $0.isSameDevice(as: latest) && hasComparableCoverage($0, latest: latest) })
            ?? latest
    }

    private func hasComparableCoverage(_ baseline: LibrarySnapshot, latest: LibrarySnapshot) -> Bool {
        let baselineCount = baseline.scannedSongCount ?? baseline.songs.count
        let latestCount = latest.scannedSongCount ?? latest.songs.count
        guard latestCount > 0 else { return true }
        guard baselineCount > 0 else { return false }
        return Double(baselineCount) / Double(latestCount) >= minimumComparableCoverageRatio
    }

    private func isPlausibleListeningDuration(
        _ listeningDuration: TimeInterval,
        monthStart: Date,
        baseline: LibrarySnapshot,
        latest: LibrarySnapshot
    ) -> Bool {
        guard listeningDuration > 0 else { return true }
        let baselineElapsed = latest.capturedAt.timeIntervalSince(baseline.capturedAt)
        let monthElapsed = latest.capturedAt.timeIntervalSince(monthStart)
        let elapsed = max(baselineElapsed, monthElapsed)
        guard elapsed > 0 else { return false }
        return listeningDuration <= elapsed * maximumListeningElapsedRatio
    }

    private func playDelta(for song: SongSnapshot, baseline: SongSnapshot?, baselineDate: Date) -> Int {
        if let baseline {
            return max(0, song.playCount - baseline.playCount)
        }

        guard let dateAdded = song.dateAdded, dateAdded >= baselineDate else {
            return 0
        }

        return max(0, song.playCount)
    }

    private func artistGroupID(for delta: SongDelta) -> String {
        if delta.latest.artistPersistentID != 0 {
            return String(delta.latest.artistPersistentID)
        }

        return "artist:\(normalizedGroupKey(delta.latest.artist))"
    }

    private func albumGroupID(for delta: SongDelta) -> String {
        if delta.latest.albumPersistentID != 0 {
            return String(delta.latest.albumPersistentID)
        }

        return [
            "album",
            normalizedGroupKey(delta.latest.albumTitle),
            normalizedGroupKey(delta.latest.artist)
        ].joined(separator: ":")
    }

    private func normalizedGroupKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func groupedDeltas(
        _ deltas: [SongDelta],
        id: (SongDelta) -> String,
        title: (SongDelta) -> String,
        subtitle: (SongDelta) -> String,
        artwork: (SongDelta) -> MPMediaItemArtwork?
    ) -> [MonthlyRecap.RankedGroup] {
        struct Accumulator {
            var title: String
            var subtitle: String
            var playDelta: Int
            var listeningDuration: TimeInterval
            var artwork: MPMediaItemArtwork?
        }

        var groups: [String: Accumulator] = [:]
        for delta in deltas {
            let key = id(delta)
            let existing = groups[key]
            groups[key] = Accumulator(
                title: existing?.title ?? title(delta),
                subtitle: existing?.subtitle ?? subtitle(delta),
                playDelta: (existing?.playDelta ?? 0) + delta.playDelta,
                listeningDuration: (existing?.listeningDuration ?? 0) + delta.listeningDuration,
                artwork: existing?.artwork ?? artwork(delta)
            )
        }

        return groups.map { key, value in
            MonthlyRecap.RankedGroup(
                id: key,
                title: value.title,
                subtitle: value.subtitle,
                playDelta: value.playDelta,
                listeningDuration: value.listeningDuration,
                artwork: value.artwork
            )
        }
        .sorted {
            if $0.playDelta == $1.playDelta {
                if $0.listeningDuration == $1.listeningDuration {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.listeningDuration > $1.listeningDuration
            }
            return $0.playDelta > $1.playDelta
        }
        .map { $0 }
    }

    private func movementSongs(
        from deltas: [SongDelta],
        baseline: LibrarySnapshot,
        latest: LibrarySnapshot,
        artworkLookup: ArtworkLookup
    ) -> [MonthlyRecap.MovementSong] {
        let baselineRanks = rankByPlayCount(for: baseline.songs)
        let latestRanks = rankByPlayCount(for: latest.songs)

        return deltas.compactMap { delta in
            guard let currentRank = latestRanks[delta.latest.id] else {
                return nil
            }

            guard let previousRank = baselineRanks[delta.latest.id] else {
                return nil
            }
            let rankChange = max(0, previousRank - currentRank)

            guard rankChange > 0 else {
                return nil
            }

            return MonthlyRecap.MovementSong(
                id: delta.latest.id,
                title: delta.latest.title,
                artist: delta.latest.artist,
                playDelta: delta.playDelta,
                rankChange: rankChange,
                currentRank: currentRank,
                previousRank: previousRank,
                artwork: artworkLookup.artwork(for: delta.latest)
            )
        }
        .sorted {
            if $0.rankChange == $1.rankChange {
                if $0.playDelta == $1.playDelta {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.playDelta > $1.playDelta
            }
            return $0.rankChange > $1.rankChange
        }
        .map { $0 }
    }

    private func rankByPlayCount(for songs: [SongSnapshot]) -> [UInt64: Int] {
        let ranked = songs.sorted {
            if $0.playCount == $1.playCount {
                if $0.playbackDuration == $1.playbackDuration {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.playbackDuration > $1.playbackDuration
            }
            return $0.playCount > $1.playCount
        }

        return Dictionary(uniqueKeysWithValues: ranked.enumerated().map { index, song in
            (song.id, index + 1)
        })
    }

    private func compareDeltas(_ lhs: SongDelta, _ rhs: SongDelta) -> Bool {
        if lhs.playDelta == rhs.playDelta {
            if lhs.listeningDuration == rhs.listeningDuration {
                return lhs.latest.title.localizedCaseInsensitiveCompare(rhs.latest.title) == .orderedAscending
            }
            return lhs.listeningDuration > rhs.listeningDuration
        }
        return lhs.playDelta > rhs.playDelta
    }

    private func loadLocked() -> StoredSnapshots {
        if let loadedSnapshots {
            return loadedSnapshots
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            let empty = StoredSnapshots(schemaVersion: 1, snapshots: [])
            loadedSnapshots = empty
            return empty
        }

        do {
            let stored = try JSONDecoder.playCount.decode(StoredSnapshots.self, from: data)
            loadedSnapshots = stored
            return stored
        } catch {
            let empty = StoredSnapshots(schemaVersion: 1, snapshots: [])
            loadedSnapshots = empty
            return empty
        }
    }

    private func saveLocked(_ stored: StoredSnapshots) {
        do {
            let data = try JSONEncoder.playCount.encode(stored)
            try data.write(to: fileURL, options: [.atomic])
            loadedSnapshots = stored
        } catch {
            assertionFailure("Failed to save monthly recap snapshots: \(error)")
        }
    }

    #if DEBUG
    func debugRunSelfCheck() -> String {
        let calendar = Calendar(identifier: .gregorian)
        let baselineDate = DateComponents(calendar: calendar, year: 2026, month: 4, day: 30, hour: 23).date!
        let latestDate = DateComponents(calendar: calendar, year: 2026, month: 5, day: 5, hour: 12).date!
        let dateAdded = DateComponents(calendar: calendar, year: 2026, month: 5, day: 2).date!

        let baseline = LibrarySnapshot(
            capturedAt: baselineDate,
            reason: .manualRefresh,
            appVersion: "self-check",
            scannedSongCount: 3,
            deviceIdentifier: "self-check",
            aggregateCounters: AggregateCounters(
                playCount: 240,
                skipCount: 1,
                listeningDuration: TimeInterval(240 * 180),
                monthNewSongCount: 0
            ),
            songs: [
                debugSong(id: 1, title: "Former First", playCount: 100),
                debugSong(id: 2, title: "Climber", playCount: 90),
                debugSong(id: 3, title: "Skip Only", playCount: 50, skipCount: 1)
            ]
        )

        let latest = LibrarySnapshot(
            capturedAt: latestDate,
            reason: .foreground,
            appVersion: "self-check",
            scannedSongCount: 4,
            deviceIdentifier: "self-check",
            aggregateCounters: AggregateCounters(
                playCount: 266,
                skipCount: 3,
                listeningDuration: TimeInterval(266 * 180),
                monthNewSongCount: 1
            ),
            songs: [
                debugSong(id: 1, title: "Former First", playCount: 101),
                debugSong(id: 2, title: "Climber", playCount: 105),
                debugSong(id: 3, title: "Skip Only", playCount: 50, skipCount: 3),
                debugSong(id: 4, title: "New Track", playCount: 10, dateAdded: dateAdded)
            ]
        )

        let recap = recap(for: latestDate, snapshots: [baseline, latest])
        var failures: [String] = []

        if recap.totalPlayDelta != 26 {
            failures.append("expected totalPlayDelta 26, got \(recap.totalPlayDelta)")
        }

        if recap.topSongs.contains(where: { $0.title == "Skip Only" }) {
            failures.append("skip-only song appeared in topSongs")
        }

        if recap.biggestGainers.map(\.title) != ["Climber"] {
            failures.append("expected only Climber as biggest gainer, got \(recap.biggestGainers.map(\.title))")
        }

        if recap.topNewSongs.map(\.title) != ["New Track"] {
            failures.append("expected only New Track as top new song, got \(recap.topNewSongs.map(\.title))")
        }

        if recap.topSongs.first?.title != "Climber" {
            failures.append("expected Climber as top song, got \(recap.topSongs.first?.title ?? "none")")
        }

        if failures.isEmpty {
            return "Recap self-check passed."
        }

        return "Recap self-check failed:\n- \(failures.joined(separator: "\n- "))"
    }

    private func debugSong(
        id: UInt64,
        title: String,
        playCount: Int,
        skipCount: Int = 0,
        dateAdded: Date? = nil
    ) -> SongSnapshot {
        SongSnapshot(
            id: id,
            title: title,
            artist: "Self Check Artist",
            albumTitle: "Self Check Album",
            playCount: playCount,
            skipCount: skipCount,
            playbackDuration: 180,
            lastPlayedDate: nil,
            dateAdded: dateAdded,
            albumPersistentID: 10,
            artistPersistentID: 20
        )
    }
    #endif
}

private extension MonthlyRecapSnapshotStore.SongSnapshot {
    init(song: TopSong) {
        self.init(
            id: song.id,
            title: song.title,
            artist: song.artist,
            albumTitle: song.albumTitle,
            playCount: song.playCount,
            skipCount: song.skipCount,
            playbackDuration: song.playbackDuration,
            lastPlayedDate: song.lastPlayedDate,
            dateAdded: song.dateAdded,
            albumPersistentID: song.albumPersistentID,
            artistPersistentID: song.artistPersistentID
        )
    }
}

private extension MonthlyRecapSnapshotStore.LibrarySnapshot {
    func logicalDeviceKey(fallbackDeviceIdentifier: String) -> String {
        deviceIdentifier ?? fallbackDeviceIdentifier
    }

    var recapMomentKey: String {
        let milliseconds = Int64((capturedAt.timeIntervalSince1970 * 1_000).rounded())
        let aggregateSignature: String
        if let aggregateCounters {
            aggregateSignature = [
                aggregateCounters.playCount,
                aggregateCounters.skipCount,
                Int((aggregateCounters.listeningDuration * 1_000).rounded()),
                aggregateCounters.monthNewSongCount
            ]
            .map(String.init)
            .joined(separator: ":")
        } else {
            aggregateSignature = counterSignature
        }

        return "\(milliseconds)|\(aggregateSignature)"
    }

    func isDuplicateRecapMoment(of snapshot: Self) -> Bool {
        guard recapMomentKey == snapshot.recapMomentKey else {
            return false
        }

        if let deviceIdentifier, let otherDeviceIdentifier = snapshot.deviceIdentifier {
            return deviceIdentifier == otherDeviceIdentifier
        }

        return true
    }

    var syncPayloadKey: String {
        "\(capturedAt.timeIntervalSince1970)|\(deviceIdentifier ?? "unknown")|\(counterSignature)"
    }

    func belongsToLocalDevice(currentDeviceIdentifier: String) -> Bool {
        deviceIdentifier == nil || deviceIdentifier == currentDeviceIdentifier
    }

    var counterSignature: String {
        songs
            .map { "\($0.id):\($0.playCount):\($0.skipCount)" }
            .joined(separator: "|")
    }

    func isSameDevice(as snapshot: Self) -> Bool {
        guard let deviceIdentifier, let otherDeviceIdentifier = snapshot.deviceIdentifier else {
            return true
        }
        return deviceIdentifier == otherDeviceIdentifier
    }

    func isRicherRecapSource(than snapshot: Self) -> Bool {
        if songs.count != snapshot.songs.count {
            return songs.count > snapshot.songs.count
        }

        let scannedSongCount = scannedSongCount ?? songs.count
        let otherScannedSongCount = snapshot.scannedSongCount ?? snapshot.songs.count
        if scannedSongCount != otherScannedSongCount {
            return scannedSongCount > otherScannedSongCount
        }

        if (deviceIdentifier != nil) != (snapshot.deviceIdentifier != nil) {
            return deviceIdentifier != nil
        }

        return capturedAt > snapshot.capturedAt
    }

    var syncIdentifier: String {
        let milliseconds = Int64((capturedAt.timeIntervalSince1970 * 1_000).rounded())
        let hash = Self.stableHash("\(milliseconds)|\(deviceIdentifier ?? "unknown")|\(counterSignature)")
        return "\(milliseconds)-\(String(hash, radix: 16))"
    }

    var syncPayload: RecapSnapshotSyncPayload? {
        syncPayload(prioritySongIDs: [], encodedRecaps: nil)
    }

    func syncPayload(
        prioritySongIDs: Set<UInt64>,
        encodedRecaps: Data? = nil,
        encodedYearlyRecaps: Data? = nil
    ) -> RecapSnapshotSyncPayload? {
        let snapshot = snapshotForSyncPayload(prioritySongIDs: prioritySongIDs)
        guard let data = try? JSONEncoder.playCount.encode(snapshot) else { return nil }
        return RecapSnapshotSyncPayload(
            id: snapshot.syncIdentifier,
            capturedAt: snapshot.capturedAt,
            counterSignature: snapshot.counterSignature,
            encodedSnapshot: data,
            encodedRecaps: encodedRecaps,
            encodedYearlyRecaps: encodedYearlyRecaps
        )
    }

    func snapshotForSyncPayload(prioritySongIDs: Set<UInt64> = []) -> Self {
        guard songs.count > MonthlyRecapSnapshotStore.minSyncedSongCount,
              let fullData = try? JSONEncoder.playCount.encode(self),
              fullData.count > MonthlyRecapSnapshotStore.maxSyncPayloadBytes else {
            return self
        }

        let rankedSongs = songs.sorted {
            let lhsIsPriority = prioritySongIDs.contains($0.id)
            let rhsIsPriority = prioritySongIDs.contains($1.id)
            if lhsIsPriority != rhsIsPriority {
                return lhsIsPriority
            }
            if $0.playCount != $1.playCount {
                return $0.playCount > $1.playCount
            }
            return $0.playbackDuration > $1.playbackDuration
        }

        var limit = rankedSongs.count
        var bestSnapshot = self
        let minimumSongCount = max(MonthlyRecapSnapshotStore.minSyncedSongCount, prioritySongIDs.count)
        while limit > minimumSongCount {
            limit = max(minimumSongCount, limit / 2)
            let candidate = Self(
                capturedAt: capturedAt,
                reason: reason,
                appVersion: appVersion,
                scannedSongCount: scannedSongCount,
                deviceIdentifier: deviceIdentifier,
                aggregateCounters: aggregateCounters,
                songs: Array(rankedSongs.prefix(limit))
            )
            bestSnapshot = candidate

            if let data = try? JSONEncoder.playCount.encode(candidate),
               data.count <= MonthlyRecapSnapshotStore.maxSyncPayloadBytes {
                return candidate
            }
        }

        return bestSnapshot
    }

    init?(syncPayload: RecapSnapshotSyncPayload) {
        guard let snapshot = try? JSONDecoder.playCount.decode(Self.self, from: syncPayload.encodedSnapshot),
              snapshot.syncIdentifier == syncPayload.id,
              snapshot.counterSignature == syncPayload.counterSignature else {
            return nil
        }
        self = snapshot
    }

    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

private extension Array where Element == MonthlyRecapSnapshotStore.LibrarySnapshot {
    func sortedForSyncPayloads() -> [Element] {
        sorted {
            if $0.capturedAt != $1.capturedAt {
                return $0.capturedAt < $1.capturedAt
            }

            let lhsDeviceIdentifier = $0.deviceIdentifier ?? ""
            let rhsDeviceIdentifier = $1.deviceIdentifier ?? ""
            if lhsDeviceIdentifier != rhsDeviceIdentifier {
                return lhsDeviceIdentifier < rhsDeviceIdentifier
            }

            if $0.songs.count != $1.songs.count {
                return $0.songs.count > $1.songs.count
            }

            return $0.syncIdentifier < $1.syncIdentifier
        }
    }
}

private extension Array where Element == RecapSnapshotSyncPayload {
    func uniquedByID() -> [Element] {
        var seenIDs = Set<String>()
        return filter { payload in
            seenIDs.insert(payload.id).inserted
        }
    }
}

private extension JSONEncoder {
    static var playCount: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var playCount: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension Calendar {
    func startOfMonth(containing date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}

private extension String {
    var normalizedArtworkKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
