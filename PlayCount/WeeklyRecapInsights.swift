import Foundation

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
            case .artistDiscovery: "Artists"
            case .songDiscovery: "Songs"
            case .listeningTime: "Listening Time"
            case .songBond: "Top Song"
            case .albumHome: "Top Album"
            case .artistEra: "Top Artist"
            case .songPlays: "Song Plays"
            case .songListeningTime: "Time With Song"
            case .albumPlays: "Album Plays"
            case .albumListeningTime: "Time With Album"
            case .artistPlays: "Artist Plays"
            case .artistListeningTime: "Time With Artist"
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
        if isEarned {
            return "Earned"
        }
        let displayedUnit = targetValue == 1 && unit == "hours" ? "hour" : unit
        return "\(formatted(currentValue)) of \(formatted(targetValue)) \(displayedUnit)"
    }

    var statusLabel: String {
        isEarned ? "Milestone unlocked" : "Milestone locked"
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
                return earned + [next]
            }
            return earned
        }
    }

    static func featuredMilestones(from milestones: [RecapMilestone], limit: Int) -> [RecapMilestone] {
        Array(
            groups(from: milestones)
                .compactMap { group in
                    group.last(where: \.isEarned) ?? group.first
                }
                .prefix(limit)
        )
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
            detail: "With \(title)",
            playThresholds: [10, 25, 50, 100, 250, 500, 1_000, 2_500],
            timeThresholds: [1, 3, 6, 12, 24, 48, 100, 250],
            playImage: "repeat"
        )
    }

    static func album(playCount: Int, listeningDuration: TimeInterval, title: String) -> [RecapMilestone] {
        milestones(
            playKind: .albumPlays,
            timeKind: .albumListeningTime,
            playCount: playCount,
            listeningDuration: listeningDuration,
            detail: "Inside \(title)",
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
            detail: "With \(name)",
            playThresholds: [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000],
            timeThresholds: [5, 10, 25, 50, 100, 250, 500, 1_000],
            playImage: "star.fill"
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
            detail: "Artists listened to in \(periodName)",
            systemImage: "person.2.wave.2.fill"
        )

        milestones += MilestoneSeriesBuilder.milestones(
            kind: .songDiscovery,
            currentValue: Double(recap.playedSongCount),
            thresholds: [25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000],
            unit: "songs",
            detail: "Songs listened to in \(periodName)",
            systemImage: "music.note.list"
        )

        let listeningHours = recap.totalListeningDuration / 3_600
        milestones += MilestoneSeriesBuilder.milestones(
            kind: .listeningTime,
            currentValue: listeningHours,
            thresholds: [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500],
            unit: "hours",
            detail: "Total listening time in \(periodName)",
            systemImage: "headphones"
        )

        if let song = recap.topSongs.first {
            let hours = song.listeningDuration / 3_600
            milestones += MilestoneSeriesBuilder.milestones(
                kind: .songBond,
                currentValue: hours,
                thresholds: [1, 3, 6, 12, 24, 48, 100, 250],
                unit: "hours",
                detail: "Listening time for \(song.title) by \(song.artist)",
                systemImage: "repeat"
            )
        }

        if let album = recap.topAlbums.first {
            let hours = album.listeningDuration / 3_600
            milestones += MilestoneSeriesBuilder.milestones(
                kind: .albumHome,
                currentValue: hours,
                thresholds: [2, 5, 10, 24, 50, 100, 250],
                unit: "hours",
                detail: "Listening time for \(album.title) by \(album.subtitle)",
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
                detail: "Listening time for \(artist.title)",
                systemImage: "star.fill"
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
