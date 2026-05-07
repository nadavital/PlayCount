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
            newSongCount: 0,
            topSongs: [],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            topNewSongs: []
        )
    }
}

final class MonthlyRecapSnapshotStore {
    fileprivate struct LibrarySnapshot: Codable {
        let capturedAt: Date
        let reason: RecapSnapshotReason?
        let appVersion: String?
        let scannedSongCount: Int?
        let songs: [SongSnapshot]
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

    private struct StoredSnapshots: Codable {
        var schemaVersion: Int
        var snapshots: [LibrarySnapshot]
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

        private static func albumKey(title: String, artist: String) -> String {
            "\(title.normalizedArtworkKey)|\(artist.normalizedArtworkKey)"
        }

        private static func artistKey(_ artist: String) -> String {
            artist.normalizedArtworkKey
        }
    }

    private let fileURL: URL
    private let calendar: Calendar
    private let accessQueue = DispatchQueue(label: "com.playcount.monthly-recap-snapshots")
    private let retentionMonths = 18
    private let minimumSnapshotInterval: TimeInterval = 60 * 30

    init(fileManager: FileManager = .default, calendar: Calendar = .current) {
        self.calendar = calendar

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("PlayCount", isDirectory: true)
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("monthly-recap-snapshots.json")
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
            recap(for: date, snapshots: load().snapshots)
        }
    }

    func recap(
        forMonthContaining date: Date,
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> MonthlyRecap {
        accessQueue.sync {
            recap(
                for: date,
                snapshots: load().snapshots,
                sourceSongs: sourceSongs,
                sourceAlbums: sourceAlbums,
                sourceArtists: sourceArtists
            )
        }
    }

    func availableMonthStarts(through date: Date = Date()) -> [Date] {
        accessQueue.sync {
            let ordered = load().snapshots.sorted { $0.capturedAt < $1.capturedAt }
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

    func debugSummary(at date: Date = Date()) -> String {
        accessQueue.sync {
            let stored = load()
            let ordered = stored.snapshots.sorted { $0.capturedAt < $1.capturedAt }
            let recap = recap(for: date, snapshots: ordered)
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
        var stored = load()
        let snapshot = LibrarySnapshot(
            capturedAt: capturedAt,
            reason: reason,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            scannedSongCount: songs.count,
            songs: songs.map(SongSnapshot.init(song:))
        )

        if shouldAppend(snapshot, after: stored.snapshots.last) {
            stored.snapshots.append(snapshot)
            stored.snapshots = retainedSnapshots(from: stored.snapshots, now: capturedAt)
            save(stored)
        }

        return recap(for: capturedAt, snapshots: stored.snapshots, sourceSongs: songs, sourceAlbums: albums, sourceArtists: artists)
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

    private func recap(
        for date: Date,
        snapshots: [LibrarySnapshot],
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> MonthlyRecap {
        let ordered = snapshots.sorted { $0.capturedAt < $1.capturedAt }
        let monthStart = calendar.startOfMonth(containing: date)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? date

        guard let latest = ordered.last(where: { $0.capturedAt < monthEnd }) else {
            return .empty(for: date, calendar: calendar)
        }

        let inMonth = ordered.filter { $0.capturedAt >= monthStart && $0.capturedAt < monthEnd }
        let baseline = baselineSnapshot(for: latest, inMonth: inMonth, ordered: ordered, monthStart: monthStart)
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.songs.map { ($0.id, $0) })
        let artworkLookup = ArtworkLookup(sourceSongs: sourceSongs, sourceAlbums: sourceAlbums, sourceArtists: sourceArtists)

        let deltas = latest.songs.compactMap { song -> SongDelta? in
            let baselineSong = baselineByID[song.id]
            let playDelta = playDelta(for: song, baseline: baselineSong, baselineDate: baseline.capturedAt)
            let skipDelta = max(0, song.skipCount - (baselineSong?.skipCount ?? song.skipCount))

            guard playDelta > 0 || skipDelta > 0 else { return nil }
            return SongDelta(latest: song, playDelta: playDelta, skipDelta: skipDelta)
        }

        let playDeltas = deltas.filter { $0.playDelta > 0 }

        let topSongs = playDeltas
            .sorted(by: compareDeltas)
            .map { rankedSong(from: $0, artworkLookup: artworkLookup) }

        let topArtists = groupedDeltas(
            playDeltas,
            id: { String($0.latest.artistPersistentID) },
            title: { $0.latest.artist },
            subtitle: { _ in "Artist" },
            artwork: { artworkLookup.artistArtwork(for: $0.latest) }
        )

        let topAlbums = groupedDeltas(
            playDeltas,
            id: { String($0.latest.albumPersistentID) },
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

        return MonthlyRecap(
            monthStart: monthStart,
            generatedAt: latest.capturedAt,
            lastCaptureReason: latest.reason,
            trackingStart: ordered.first?.capturedAt,
            snapshotCount: inMonth.count,
            totalPlayDelta: deltas.reduce(0) { $0 + $1.playDelta },
            totalSkipDelta: deltas.reduce(0) { $0 + $1.skipDelta },
            totalListeningDuration: deltas.reduce(0) { $0 + $1.listeningDuration },
            newSongCount: newSongCount,
            topSongs: topSongs,
            topArtists: topArtists,
            topAlbums: topAlbums,
            biggestGainers: biggestGainers,
            topNewSongs: topNewSongs
        )
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
        if let beforeMonth = ordered.last(where: { $0.capturedAt < monthStart }) {
            return beforeMonth
        }

        let earlierInMonth = inMonth.filter { $0.capturedAt < latest.capturedAt }

        if let firstDifferent = earlierInMonth.first(where: { $0.counterSignature != latest.counterSignature }) {
            return firstDifferent
        }

        return earlierInMonth.first ?? inMonth.first ?? latest
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

    private func load() -> StoredSnapshots {
        guard let data = try? Data(contentsOf: fileURL) else {
            return StoredSnapshots(schemaVersion: 1, snapshots: [])
        }

        do {
            return try JSONDecoder.playCount.decode(StoredSnapshots.self, from: data)
        } catch {
            return StoredSnapshots(schemaVersion: 1, snapshots: [])
        }
    }

    private func save(_ stored: StoredSnapshots) {
        do {
            let data = try JSONEncoder.playCount.encode(stored)
            try data.write(to: fileURL, options: [.atomic])
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
    var counterSignature: String {
        songs
            .map { "\($0.id):\($0.playCount):\($0.skipCount)" }
            .joined(separator: "|")
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

private extension Calendar {
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
