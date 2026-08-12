import Foundation
import SQLite3

struct WeeklyRecapInsight: Equatable, Sendable {
    struct RankedSong: Equatable, Sendable {
        let id: UInt64
        let title: String
        let artist: String
        let playDelta: Int
    }

    let weekStart: Date
    let generatedAt: Date
    let trackingStart: Date
    let snapshotCount: Int
    let totalPlayDelta: Int
    let totalListeningDuration: TimeInterval
    let topSong: RankedSong?

    var hasActivity: Bool {
        totalPlayDelta > 0 || totalListeningDuration > 0
    }

    static func empty(for date: Date, calendar: Calendar = .current) -> WeeklyRecapInsight {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return WeeklyRecapInsight(
            weekStart: start,
            generatedAt: date,
            trackingStart: date,
            snapshotCount: 0,
            totalPlayDelta: 0,
            totalListeningDuration: 0,
            topSong: nil
        )
    }
}

struct WeeklyRecapComparison: Equatable, Sendable {
    let current: WeeklyRecapInsight
    let previous: WeeklyRecapInsight?
    let history: [WeeklyRecapInsight]

    init(
        current: WeeklyRecapInsight,
        previous: WeeklyRecapInsight?,
        history: [WeeklyRecapInsight]? = nil
    ) {
        self.current = current
        self.previous = previous
        let source = history ?? [previous, current].compactMap { $0 }
        self.history = Dictionary(grouping: source, by: \.weekStart)
            .compactMap { $0.value.max { $0.generatedAt < $1.generatedAt } }
            .sorted { $0.weekStart < $1.weekStart }
    }

    static func empty(at date: Date = Date(), calendar: Calendar = .current) -> WeeklyRecapComparison {
        WeeklyRecapComparison(current: .empty(for: date, calendar: calendar), previous: nil)
    }
}

struct RecapMilestone: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case artistDiscovery
        case songDiscovery
        case listeningTime
        case songBond
        case albumHome
        case artistEra
        case songPlays
        case songListeningTime
        case albumPlays
        case albumListeningTime
        case artistPlays
        case artistListeningTime

        var collectionTitle: String {
            switch self {
            case .artistDiscovery: "Artists Heard This Year"
            case .songDiscovery: "Songs Heard This Year"
            case .listeningTime: "Listening This Year"
            case .songBond: "Time With Your Top Song"
            case .albumHome: "Time With Your Top Album"
            case .artistEra: "Time With Your Top Artist"
            case .songPlays: "Song Plays"
            case .songListeningTime: "Time With This Song"
            case .albumPlays: "Track Plays From This Album"
            case .albumListeningTime: "Time With This Album"
            case .artistPlays: "Artist Plays"
            case .artistListeningTime: "Time With This Artist"
            }
        }
    }

    let kind: Kind
    let title: String
    let detail: String
    let systemImage: String
    let currentValue: Double
    let targetValue: Double
    let unit: String
    let earnedTarget: Double?
    let stage: Int

    var id: String { "\(kind.rawValue)-\(targetValue)" }

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }

    var isEarned: Bool {
        earnedTarget != nil
    }

    var valueLabel: String {
        let displayedUnit = targetValue == 1 && unit == "hours" ? "hour" : unit
        if isEarned {
            return "\(formatted(targetValue)) \(displayedUnit) earned"
        }
        return "\(formatted(currentValue)) of \(formatted(targetValue)) \(displayedUnit)"
    }

    var targetLabel: String {
        formatted(targetValue)
    }

    var compactValueLabel: String {
        isEarned ? "" : "Next milestone"
    }

    var currentValueLabel: String {
        let displayedUnit = currentValue == 1 && unit == "hours" ? "hour" : unit
        return "\(formatted(currentValue)) \(displayedUnit)"
    }

    var statusLabel: String {
        isEarned ? "Milestone unlocked" : "Milestone locked"
    }

    var achievementDescription: String {
        let target = formatted(targetValue)
        let hours = targetValue == 1 ? "hour" : "hours"
        switch kind {
        case .artistDiscovery:
            return "You listened to \(target) artists this year."
        case .songDiscovery:
            return "You listened to \(target) songs this year."
        case .listeningTime:
            return "You listened to music for \(target) \(hours) this year."
        case .songBond, .songListeningTime:
            return "You've listened to \(detail) for \(target) \(hours)."
        case .albumHome, .albumListeningTime:
            return "You've listened to \(detail) for \(target) \(hours)."
        case .artistEra, .artistListeningTime:
            return "You've listened to \(detail) for \(target) \(hours)."
        case .songPlays:
            return "You've played \(detail) \(target) times."
        case .albumPlays:
            return "Tracks from \(detail) reached \(target) plays."
        case .artistPlays:
            return "Songs by \(detail) reached \(target) plays."
        }
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
}

enum MilestoneCollectionPresentation {
    static func groups(from milestones: [RecapMilestone]) -> [[RecapMilestone]] {
        var order: [RecapMilestone.Kind] = []
        var grouped: [RecapMilestone.Kind: [RecapMilestone]] = [:]
        for milestone in milestones {
            if grouped[milestone.kind] == nil {
                order.append(milestone.kind)
            }
            grouped[milestone.kind, default: []].append(milestone)
        }
        return order.compactMap { kind in
            grouped[kind]?.sorted { $0.targetValue < $1.targetValue }
        }
    }

    static func visibleMilestones(from milestones: [RecapMilestone]) -> [RecapMilestone] {
        groups(from: milestones).flatMap { group in
            let earned = group.filter(\.isEarned)
            if let next = group.first(where: { !$0.isEarned }) {
                return ([next] + earned.reversed()).map { $0 }
            }
            return Array(earned.reversed())
        }
    }

    static func featuredMilestones(from milestones: [RecapMilestone], limit: Int) -> [RecapMilestone] {
        Array(
            groups(from: milestones)
                .compactMap { group in
                    let nearby = group.first { !$0.isEarned && $0.progress >= 0.7 }
                    return nearby ?? group.last(where: \.isEarned) ?? group.first
                }
                .prefix(limit)
        )
    }

    static func newlyEarned(
        current: [RecapMilestone],
        previous: [RecapMilestone]
    ) -> [RecapMilestone] {
        let previouslyEarned = Set(previous.lazy.filter(\.isEarned).map(\.id))
        return current.filter { $0.isEarned && !previouslyEarned.contains($0.id) }
    }

    static func monthlyHighlights(
        current: [RecapMilestone],
        previous: [RecapMilestone],
        nearbyLimit: Int = 2
    ) -> [RecapMilestone] {
        let unlocked = newlyEarned(current: current, previous: previous)
        let unlockedIDs = Set(unlocked.map(\.id))
        let nearby = groups(from: current)
            .compactMap { $0.first(where: { !$0.isEarned && $0.progress >= 0.7 }) }
            .filter { !unlockedIDs.contains($0.id) }
            .sorted { $0.progress > $1.progress }
        return unlocked + nearby.prefix(nearbyLimit)
    }

    static func progressSummary(from milestones: [RecapMilestone]) -> [MilestoneProgressSummary] {
        groups(from: milestones).compactMap { group in
            guard let first = group.first else { return nil }
            let highestEarned = group.last(where: \.isEarned)
            let next = group.first(where: { !$0.isEarned })
            guard let featured = highestEarned ?? next else { return nil }
            return MilestoneProgressSummary(
                kind: first.kind,
                featured: featured,
                highestEarned: highestEarned,
                next: next,
                series: group
            )
        }
    }
}

struct MilestoneProgressSummary: Identifiable, Equatable, Sendable {
    let kind: RecapMilestone.Kind
    let featured: RecapMilestone
    let highestEarned: RecapMilestone?
    let next: RecapMilestone?
    let series: [RecapMilestone]

    var id: RecapMilestone.Kind { kind }
}

final class MediaMilestoneLedger: @unchecked Sendable {
    enum Scope: String, Sendable {
        case song
        case album
        case artist
    }

    struct HighestObservedValues: Codable, Equatable, Sendable {
        var playCount: Int
        var listeningDuration: TimeInterval
        var lastObservedAt: Date
    }

    private let fileURL: URL
    private let databaseQueue = DispatchQueue(label: "PlayCount.MediaMilestoneLedger")
    private let cacheLock = NSLock()
    private var activeValues: [String: HighestObservedValues] = [:]
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func hydrateCache() {
        let values = databaseQueue.sync { () -> [String: HighestObservedValues] in
            guard let database = openDatabase() else { return [:] }
            defer { sqlite3_close(database) }
            return allStoredValues(in: database)
        }
        cacheLock.withLock {
            for (key, value) in values {
                activeValues[key] = merged(activeValues[key], with: value)
            }
        }
    }

    func hydrateCache(songs: [TopSong], albums: [TopAlbum], artists: [TopArtist]) {
        let albumAliases = aliasCounts(albums.map(Self.albumMetadataIdentity))
        let artistAliases = aliasCounts(artists.map(Self.artistMetadataIdentity))
        let keys = songs.flatMap { Self.songIdentities($0).map { recordKey(scope: .song, identity: $0) } }
            + albums.flatMap {
                Self.albumIdentities($0, includesMetadataAlias: albumAliases[Self.albumMetadataIdentity($0)] == 1)
                    .map { recordKey(scope: .album, identity: $0) }
            }
            + artists.flatMap {
                Self.artistIdentities($0, includesMetadataAlias: artistAliases[Self.artistMetadataIdentity($0)] == 1)
                    .map { recordKey(scope: .artist, identity: $0) }
            }
        let values = databaseQueue.sync { () -> [String: HighestObservedValues] in
            guard let database = openDatabase() else { return [:] }
            defer { sqlite3_close(database) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT play_count, listening_duration, observed_at FROM milestone_values WHERE key = ?",
                -1,
                &statement,
                nil
            ) == SQLITE_OK, let statement else { return [:] }
            defer { sqlite3_finalize(statement) }
            var loaded: [String: HighestObservedValues] = [:]
            loaded.reserveCapacity(keys.count)
            for key in keys {
                guard sqlite3_reset(statement) == SQLITE_OK,
                      sqlite3_clear_bindings(statement) == SQLITE_OK,
                      sqlite3_bind_text(statement, 1, key, -1, Self.transient) == SQLITE_OK,
                      sqlite3_step(statement) == SQLITE_ROW else { continue }
                loaded[key] = HighestObservedValues(
                    playCount: Int(sqlite3_column_int64(statement, 0)),
                    listeningDuration: sqlite3_column_double(statement, 1),
                    lastObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                )
            }
            return loaded
        }
        cacheLock.withLock {
            for (key, value) in values {
                activeValues[key] = merged(activeValues[key], with: value)
            }
        }
    }

    func observe(
        scope: Scope,
        identity: String,
        playCount: Int,
        listeningDuration: TimeInterval,
        at date: Date = Date()
    ) {
        let key = recordKey(scope: scope, identity: identity)
        _ = databaseQueue.sync { () -> HighestObservedValues? in
            guard let database = openDatabase() else { return nil }
            defer { sqlite3_close(database) }
            let stored = upsert(
                key: key,
                playCount: playCount,
                listeningDuration: listeningDuration,
                observedAt: date,
                in: database
            )
            if let stored {
                cacheLock.withLock { activeValues[key] = stored }
            }
            return stored
        }
    }

    func highestObserved(
        scope: Scope,
        identities: [String],
        currentPlayCount: Int,
        currentListeningDuration: TimeInterval
    ) -> HighestObservedValues {
        let cached = cacheLock.withLock {
            identities.compactMap { activeValues[recordKey(scope: scope, identity: $0)] }
                .reduce(nil as HighestObservedValues?) { partial, value in
                    merged(partial, with: value)
                }
        }
        return HighestObservedValues(
            playCount: max(cached?.playCount ?? 0, currentPlayCount),
            listeningDuration: max(cached?.listeningDuration ?? 0, currentListeningDuration),
            lastObservedAt: cached?.lastObservedAt ?? Date()
        )
    }

    func highestObserved(
        scope: Scope,
        identity: String,
        currentPlayCount: Int,
        currentListeningDuration: TimeInterval
    ) -> HighestObservedValues {
        highestObserved(
            scope: scope,
            identities: [identity],
            currentPlayCount: currentPlayCount,
            currentListeningDuration: currentListeningDuration
        )
    }

    func observe(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist],
        at date: Date = Date(),
        shouldCommit: @escaping @Sendable () -> Bool = { true }
    ) {
        let albumAliases = aliasCounts(albums.map(Self.albumMetadataIdentity))
        let artistAliases = aliasCounts(artists.map(Self.artistMetadataIdentity))
        let identityBridges = albums.compactMap { album -> (Scope, String, String)? in
            let metadata = Self.albumMetadataIdentity(album)
            guard album.id != 0, albumAliases[metadata] == 1 else { return nil }
            return (.album, "persistent:\(album.id)", metadata)
        } + artists.compactMap { artist -> (Scope, String, String)? in
            let metadata = Self.artistMetadataIdentity(artist)
            guard artist.id != 0, artistAliases[metadata] == 1 else { return nil }
            return (.artist, "persistent:\(artist.id)", metadata)
        }
        let observations = songs.flatMap { song in
            Self.songIdentities(song).map { (Scope.song, $0, song.playCount, song.totalPlayDuration) }
        } + albums.flatMap { album in
            let aliases = Self.albumIdentities(
                album,
                includesMetadataAlias: albumAliases[Self.albumMetadataIdentity(album)] == 1
            )
            return aliases.map {
                (Scope.album, $0, album.playCount, album.totalPlayDuration)
            }
        } + artists.flatMap { artist in
            let aliases = Self.artistIdentities(
                artist,
                includesMetadataAlias: artistAliases[Self.artistMetadataIdentity(artist)] == 1
            )
            return aliases.map {
                (Scope.artist, $0, artist.playCount, artist.totalPlayDuration)
            }
        }
        _ = databaseQueue.sync { () -> [String: HighestObservedValues]? in
            guard shouldCommit(), let database = openDatabase() else { return nil }
            defer { sqlite3_close(database) }
            guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
                return nil
            }
            var values: [String: HighestObservedValues] = [:]
            values.reserveCapacity(observations.count)
            guard let statement = preparedUpsert(in: database) else {
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                return nil
            }
            defer { sqlite3_finalize(statement) }
            var bridgeValues: [String: HighestObservedValues] = [:]
            for (scope, persistentIdentity, metadataIdentity) in identityBridges {
                let metadataKey = recordKey(scope: scope, identity: metadataIdentity)
                if let aliasValue = storedValues(for: metadataKey, in: database) {
                    bridgeValues[recordKey(scope: scope, identity: persistentIdentity)] = aliasValue
                }
            }
            for (scope, identity, playCount, listeningDuration) in observations {
                let key = recordKey(scope: scope, identity: identity)
                let bridged = bridgeValues[key]
                guard let stored = upsert(
                    key: key,
                    playCount: max(playCount, bridged?.playCount ?? 0),
                    listeningDuration: max(listeningDuration, bridged?.listeningDuration ?? 0),
                    observedAt: date,
                    using: statement
                ) else {
                    sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                    return nil
                }
                values[key] = stored
            }
            guard shouldCommit(), sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
                return nil
            }
            cacheLock.withLock {
                for (key, value) in values {
                    activeValues[key] = merged(activeValues[key], with: value)
                }
            }
            return values
        }
    }

    static func songIdentity(_ song: TopSong) -> String {
        if !song.playbackStoreID.isEmpty {
            return "store:\(song.playbackStoreID)"
        }
        return "metadata:\(normalized(song.title))|\(normalized(song.artist))|\(normalized(song.albumTitle))"
    }

    static func songIdentities(_ song: TopSong) -> [String] {
        [songIdentity(song)]
    }

    static func albumIdentity(_ album: TopAlbum) -> String {
        if album.id != 0 {
            return "persistent:\(album.id)"
        }
        return "metadata:\(normalized(album.title))|\(normalized(album.artist))"
    }

    static func albumIdentities(_ album: TopAlbum, includesMetadataAlias: Bool = true) -> [String] {
        let metadata = albumMetadataIdentity(album)
        guard album.id != 0 else { return [metadata] }
        return includesMetadataAlias ? ["persistent:\(album.id)", metadata] : ["persistent:\(album.id)"]
    }

    static func artistIdentity(_ artist: TopArtist) -> String {
        if artist.id != 0 {
            return "persistent:\(artist.id)"
        }
        return "metadata:\(normalized(artist.name))"
    }

    static func artistIdentities(_ artist: TopArtist, includesMetadataAlias: Bool = true) -> [String] {
        let metadata = artistMetadataIdentity(artist)
        guard artist.id != 0 else { return [metadata] }
        return includesMetadataAlias ? ["persistent:\(artist.id)", metadata] : ["persistent:\(artist.id)"]
    }

    static func albumMetadataIdentity(_ album: TopAlbum) -> String {
        "metadata:\(normalized(album.title))|\(normalized(album.artist))"
    }

    static func artistMetadataIdentity(_ artist: TopArtist) -> String {
        "metadata:\(normalized(artist.name))"
    }

    private func aliasCounts(_ aliases: [String]) -> [String: Int] {
        aliases.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private func recordKey(scope: Scope, identity: String) -> String {
        "\(scope.rawValue)|\(identity)"
    }

    private func openDatabase() -> OpaquePointer? {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            fileURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            return nil
        }
        sqlite3_busy_timeout(database, 1_000)
        guard sqlite3_exec(database, "PRAGMA journal_mode=WAL", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(database, "PRAGMA synchronous=FULL", nil, nil, nil) == SQLITE_OK,
              sqlite3_exec(
                database,
                "CREATE TABLE IF NOT EXISTS milestone_values (key TEXT PRIMARY KEY, play_count INTEGER NOT NULL, listening_duration REAL NOT NULL, observed_at REAL NOT NULL)",
                nil,
                nil,
                nil
              ) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        return database
    }

    private func upsert(
        key: String,
        playCount: Int,
        listeningDuration: TimeInterval,
        observedAt: Date,
        in database: OpaquePointer
    ) -> HighestObservedValues? {
        guard let statement = preparedUpsert(in: database) else { return nil }
        defer { sqlite3_finalize(statement) }
        return upsert(
            key: key,
            playCount: playCount,
            listeningDuration: listeningDuration,
            observedAt: observedAt,
            using: statement
        )
    }

    private func preparedUpsert(in database: OpaquePointer) -> OpaquePointer? {
        let sql = """
        INSERT INTO milestone_values(key, play_count, listening_duration, observed_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            play_count = MAX(play_count, excluded.play_count),
            listening_duration = MAX(listening_duration, excluded.listening_duration),
            observed_at = CASE
                WHEN excluded.play_count > play_count OR excluded.listening_duration > listening_duration
                THEN excluded.observed_at ELSE observed_at END
        RETURNING play_count, listening_duration, observed_at
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        return statement
    }

    private func upsert(
        key: String,
        playCount: Int,
        listeningDuration: TimeInterval,
        observedAt: Date,
        using statement: OpaquePointer
    ) -> HighestObservedValues? {
        guard sqlite3_reset(statement) == SQLITE_OK,
              sqlite3_clear_bindings(statement) == SQLITE_OK,
              sqlite3_bind_text(statement, 1, key, -1, Self.transient) == SQLITE_OK,
              sqlite3_bind_int64(statement, 2, sqlite3_int64(max(0, playCount))) == SQLITE_OK,
              sqlite3_bind_double(statement, 3, max(0, listeningDuration)) == SQLITE_OK,
              sqlite3_bind_double(statement, 4, observedAt.timeIntervalSince1970) == SQLITE_OK else {
            return nil
        }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let values = HighestObservedValues(
            playCount: Int(sqlite3_column_int64(statement, 0)),
            listeningDuration: sqlite3_column_double(statement, 1),
            lastObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        )
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        return values
    }

    private func allStoredValues(in database: OpaquePointer) -> [String: HighestObservedValues] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT key, play_count, listening_duration, observed_at FROM milestone_values",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return [:] }
        defer { sqlite3_finalize(statement) }
        var values: [String: HighestObservedValues] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyText = sqlite3_column_text(statement, 0) else { continue }
            values[String(cString: keyText)] = HighestObservedValues(
                playCount: Int(sqlite3_column_int64(statement, 1)),
                listeningDuration: sqlite3_column_double(statement, 2),
                lastObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
            )
        }
        return values
    }

    private func storedValues(for key: String, in database: OpaquePointer) -> HighestObservedValues? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT play_count, listening_duration, observed_at FROM milestone_values WHERE key = ?",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, key, -1, Self.transient) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return HighestObservedValues(
            playCount: Int(sqlite3_column_int64(statement, 0)),
            listeningDuration: sqlite3_column_double(statement, 1),
            lastObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        )
    }

    private func merged(
        _ existing: HighestObservedValues?,
        with incoming: HighestObservedValues
    ) -> HighestObservedValues {
        HighestObservedValues(
            playCount: max(existing?.playCount ?? 0, incoming.playCount),
            listeningDuration: max(existing?.listeningDuration ?? 0, incoming.listeningDuration),
            lastObservedAt: max(existing?.lastObservedAt ?? .distantPast, incoming.lastObservedAt)
        )
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PlayCount/milestone-values.sqlite", isDirectory: false)
    }
}

private enum MilestoneSeriesBuilder {
    static func milestones(
        kind: RecapMilestone.Kind,
        currentValue: Double,
        thresholds: [Double],
        unit: String,
        detail: String,
        systemImage: String
    ) -> [RecapMilestone] {
        thresholds.enumerated().map { index, target in
            let earned = currentValue >= target
            return RecapMilestone(
                kind: kind,
                title: thresholdTitle(target: target, unit: unit),
                detail: detail,
                systemImage: systemImage,
                currentValue: currentValue,
                targetValue: target,
                unit: unit,
                earnedTarget: earned ? target : nil,
                stage: stage(index: index, count: thresholds.count)
            )
        }
    }

    private static func thresholdTitle(target: Double, unit: String) -> String {
        let number = target.rounded() == target
            ? Int(target).formatted()
            : target.formatted(.number.precision(.fractionLength(1)))
        let label: String
        if target == 1, unit.hasSuffix("s") {
            label = String(unit.dropLast()).capitalized
        } else {
            label = unit.capitalized
        }
        return "\(number) \(label)"
    }

    private static func stage(index: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }

        // Every threshold in a collection must be visually distinct. Reserve
        // the final three stages for the increasingly elaborate Rose Gold,
        // Platinum, and Legend medals, regardless of collection length.
        let specialStageCount = min(3, count)
        let firstSpecialIndex = count - specialStageCount
        if index >= firstSpecialIndex {
            return 9 - specialStageCount + (index - firstSpecialIndex)
        }
        return index
    }
}

enum MediaMilestoneEngine {
    static func song(playCount: Int, listeningDuration: TimeInterval, title: String) -> [RecapMilestone] {
        milestones(
            playKind: .songPlays,
            timeKind: .songListeningTime,
            playCount: playCount,
            listeningDuration: listeningDuration,
            detail: title,
            playThresholds: [10, 25, 50, 100, 250, 500, 1_000, 2_500],
            timeThresholds: [1, 3, 6, 12, 24, 48, 100, 250],
            playImage: "play.fill"
        )
    }

    static func album(playCount: Int, listeningDuration: TimeInterval, title: String) -> [RecapMilestone] {
        milestones(
            playKind: .albumPlays,
            timeKind: .albumListeningTime,
            playCount: playCount,
            listeningDuration: listeningDuration,
            detail: title,
            playThresholds: [25, 50, 100, 250, 500, 1_000, 2_500, 5_000],
            timeThresholds: [2, 5, 10, 24, 50, 100, 250, 500],
            playImage: "rectangle.stack.fill"
        )
    }

    static func artist(playCount: Int, listeningDuration: TimeInterval, name: String) -> [RecapMilestone] {
        milestones(
            playKind: .artistPlays,
            timeKind: .artistListeningTime,
            playCount: playCount,
            listeningDuration: listeningDuration,
            detail: name,
            playThresholds: [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000],
            timeThresholds: [5, 10, 25, 50, 100, 250, 500, 1_000],
            playImage: "waveform"
        )
    }

    private static func milestones(
        playKind: RecapMilestone.Kind,
        timeKind: RecapMilestone.Kind,
        playCount: Int,
        listeningDuration: TimeInterval,
        detail: String,
        playThresholds: [Double],
        timeThresholds: [Double],
        playImage: String
    ) -> [RecapMilestone] {
        let listeningHours = listeningDuration / 3_600
        return MilestoneSeriesBuilder.milestones(
            kind: playKind,
            currentValue: Double(playCount),
            thresholds: playThresholds,
            unit: "plays",
            detail: detail,
            systemImage: playImage
        ) + MilestoneSeriesBuilder.milestones(
            kind: timeKind,
            currentValue: listeningHours,
            thresholds: timeThresholds,
            unit: "hours",
            detail: detail,
            systemImage: "clock"
        )
    }
}

enum RecapMilestoneEngine {
    static func milestones(for recap: MonthlyRecap, periodName: String) -> [RecapMilestone] {
        var milestones: [RecapMilestone] = []

        let artistCount = recap.listenedArtistCount
        milestones += MilestoneSeriesBuilder.milestones(
            kind: .artistDiscovery,
            currentValue: Double(artistCount),
            thresholds: [10, 25, 50, 100, 250, 500, 1_000],
            unit: "artists",
            detail: periodName,
            systemImage: "person.2.fill"
        )

        milestones += MilestoneSeriesBuilder.milestones(
            kind: .songDiscovery,
            currentValue: Double(recap.playedSongCount),
            thresholds: [25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000],
            unit: "songs",
            detail: periodName,
            systemImage: "music.note"
        )

        let listeningHours = recap.totalListeningDuration / 3_600
        milestones += MilestoneSeriesBuilder.milestones(
            kind: .listeningTime,
            currentValue: listeningHours,
            thresholds: [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500],
            unit: "hours",
            detail: periodName,
            systemImage: "headphones"
        )

        if let song = recap.topSongs.first {
            let hours = song.listeningDuration / 3_600
            milestones += MilestoneSeriesBuilder.milestones(
                kind: .songBond,
                currentValue: hours,
                thresholds: [1, 3, 6, 12, 24, 48, 100, 250],
                unit: "hours",
                detail: "\(song.title) by \(song.artist)",
                systemImage: "music.note"
            )
        }

        if let album = recap.topAlbums.first {
            let hours = album.listeningDuration / 3_600
            milestones += MilestoneSeriesBuilder.milestones(
                kind: .albumHome,
                currentValue: hours,
                thresholds: [2, 5, 10, 24, 50, 100, 250],
                unit: "hours",
                detail: "\(album.title) by \(album.subtitle)",
                systemImage: "rectangle.stack.fill"
            )
        }

        if let artist = recap.topArtists.first {
            let hours = artist.listeningDuration / 3_600
            milestones += MilestoneSeriesBuilder.milestones(
                kind: .artistEra,
                currentValue: hours,
                thresholds: [5, 10, 25, 50, 100, 250, 500],
                unit: "hours",
                detail: artist.title,
                systemImage: "waveform"
            )
        }

        return milestones
    }
}

final class WeeklyRecapInsightStore: @unchecked Sendable {
    private struct StoredSong: Codable, Equatable {
        let id: UInt64
        let title: String
        let artist: String
        var playDelta: Int
    }

    private struct Bucket: Codable, Equatable {
        let weekStart: Date
        var generatedAt: Date
        let trackingStart: Date
        var snapshotCount: Int
        var totalPlayDelta: Int
        var totalListeningDuration: TimeInterval
        var songs: [String: StoredSong]
    }

    private struct Observation: Codable, Equatable {
        let capturedAt: Date
        let monthStart: Date
        let totalPlayDelta: Int
        let totalListeningDuration: TimeInterval
        let songs: [String: StoredSong]
    }

    private struct StoredInsights: Codable {
        var buckets: [Bucket]
        var observation: Observation?

        static let empty = StoredInsights(buckets: [], observation: nil)
    }

    private let fileURL: URL
    private let calendar: Calendar
    private let accessQueue = DispatchQueue(label: "com.nadavavital.PlayCount.weekly-recap-insights")
    private let retentionWeekCount = 18

    init(directoryURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        let directory = directoryURL ?? Self.defaultDirectoryURL()
        fileURL = directory.appendingPathComponent("weekly-recap-insights.json")
    }

    func record(recap: MonthlyRecap, at capturedAt: Date) -> WeeklyRecapComparison {
        accessQueue.sync {
            var stored = load()
            let currentWeekStart = weekStart(containing: capturedAt)
            let songs = songObservation(from: recap)
            let observation = Observation(
                capturedAt: capturedAt,
                monthStart: recap.monthStart,
                totalPlayDelta: recap.totalPlayDelta,
                totalListeningDuration: recap.totalListeningDuration,
                songs: songs
            )

            if let previous = stored.observation,
               calendar.isDate(previous.capturedAt, equalTo: capturedAt, toGranularity: .weekOfYear),
               calendar.component(.yearForWeekOfYear, from: previous.capturedAt) == calendar.component(.yearForWeekOfYear, from: capturedAt) {
                updateCurrentBucket(
                    in: &stored,
                    weekStart: currentWeekStart,
                    previous: previous,
                    current: observation
                )
            } else {
                establishBaseline(in: &stored, weekStart: currentWeekStart, observation: observation)
            }

            stored.observation = observation
            stored.buckets = retainedBuckets(stored.buckets, currentWeekStart: currentWeekStart)
            save(stored)
            return comparison(from: stored, at: capturedAt)
        }
    }

    func currentComparison(at date: Date = Date()) -> WeeklyRecapComparison {
        accessQueue.sync {
            comparison(from: load(), at: date)
        }
    }

    private func updateCurrentBucket(
        in stored: inout StoredInsights,
        weekStart: Date,
        previous: Observation,
        current: Observation
    ) {
        let sameMonth = calendar.isDate(previous.monthStart, equalTo: current.monthStart, toGranularity: .month)
        let playDelta = sameMonth
            ? max(0, current.totalPlayDelta - previous.totalPlayDelta)
            : max(0, current.totalPlayDelta)
        let listeningDelta = sameMonth
            ? max(0, current.totalListeningDuration - previous.totalListeningDuration)
            : max(0, current.totalListeningDuration)

        let index = stored.buckets.firstIndex { $0.weekStart == weekStart }
        var bucket = index.map { stored.buckets[$0] } ?? Bucket(
            weekStart: weekStart,
            generatedAt: current.capturedAt,
            trackingStart: previous.capturedAt,
            snapshotCount: 1,
            totalPlayDelta: 0,
            totalListeningDuration: 0,
            songs: [:]
        )
        bucket.generatedAt = current.capturedAt
        bucket.snapshotCount += 1
        bucket.totalPlayDelta += playDelta
        bucket.totalListeningDuration += listeningDelta

        for (identity, song) in current.songs {
            let previousCount = sameMonth ? (previous.songs[identity]?.playDelta ?? 0) : 0
            let delta = max(0, song.playDelta - previousCount)
            guard delta > 0 else { continue }
            var accumulated = bucket.songs[identity] ?? StoredSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                playDelta: 0
            )
            accumulated.playDelta += delta
            bucket.songs[identity] = accumulated
        }
        bucket.songs = Dictionary(
            uniqueKeysWithValues: bucket.songs
                .sorted {
                    if $0.value.playDelta != $1.value.playDelta {
                        return $0.value.playDelta > $1.value.playDelta
                    }
                    return $0.value.title.localizedCaseInsensitiveCompare($1.value.title) == .orderedAscending
                }
                .prefix(25)
                .map { ($0.key, $0.value) }
        )

        if let index {
            stored.buckets[index] = bucket
        } else {
            stored.buckets.append(bucket)
        }
    }

    private func establishBaseline(
        in stored: inout StoredInsights,
        weekStart: Date,
        observation: Observation
    ) {
        guard !stored.buckets.contains(where: { $0.weekStart == weekStart }) else { return }
        stored.buckets.append(
            Bucket(
                weekStart: weekStart,
                generatedAt: observation.capturedAt,
                trackingStart: observation.capturedAt,
                snapshotCount: 1,
                totalPlayDelta: 0,
                totalListeningDuration: 0,
                songs: [:]
            )
        )
    }

    private func songObservation(from recap: MonthlyRecap) -> [String: StoredSong] {
        Dictionary(uniqueKeysWithValues: recap.topSongs.map { song in
            let identity = song.recordingIdentity ?? "legacy:\(song.title.lowercased())|\(song.artist.lowercased())|\(song.albumTitle.lowercased())"
            return (
                identity,
                StoredSong(id: song.id, title: song.title, artist: song.artist, playDelta: song.playDelta)
            )
        })
    }

    private func comparison(from stored: StoredInsights, at date: Date) -> WeeklyRecapComparison {
        let currentWeekStart = weekStart(containing: date)
        let ordered = stored.buckets.sorted { $0.weekStart < $1.weekStart }
        let currentBucket = ordered.last { $0.weekStart == currentWeekStart }
        let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)
        let previousBucket = previousWeekStart.flatMap { expectedStart in
            ordered.last { $0.weekStart == expectedStart }
        }
        return WeeklyRecapComparison(
            current: currentBucket.map(insight(from:)) ?? .empty(for: date, calendar: calendar),
            previous: previousBucket.map(insight(from:)),
            history: ordered.suffix(8).map(insight(from:))
        )
    }

    private func insight(from bucket: Bucket) -> WeeklyRecapInsight {
        let topSong = bucket.songs.values.sorted {
            if $0.playDelta != $1.playDelta { return $0.playDelta > $1.playDelta }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }.first
        return WeeklyRecapInsight(
            weekStart: bucket.weekStart,
            generatedAt: bucket.generatedAt,
            trackingStart: bucket.trackingStart,
            snapshotCount: bucket.snapshotCount,
            totalPlayDelta: bucket.totalPlayDelta,
            totalListeningDuration: bucket.totalListeningDuration,
            topSong: topSong.map {
                WeeklyRecapInsight.RankedSong(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    playDelta: $0.playDelta
                )
            }
        )
    }

    private func retainedBuckets(_ buckets: [Bucket], currentWeekStart: Date) -> [Bucket] {
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -(retentionWeekCount - 1), to: currentWeekStart) else {
            return buckets
        }
        return buckets.filter { $0.weekStart >= cutoff }.sorted { $0.weekStart < $1.weekStart }
    }

    private func weekStart(containing date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    private func load() -> StoredInsights {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(StoredInsights.self, from: data) else {
            return .empty
        }
        return stored
    }

    private func save(_ stored: StoredInsights) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(stored)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to save weekly recap insights: \(error)")
            #endif
        }
    }

    private static func defaultDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("PlayCount", isDirectory: true)
    }
}
