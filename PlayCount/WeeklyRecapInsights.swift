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

    var id: String { kind.rawValue }

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue, 0), 1)
    }

    var isEarned: Bool {
        earnedTarget != nil
    }

    var valueLabel: String {
        let displayedUnit = targetValue == 1 && unit == "hours" ? "hour" : unit
        return "\(formatted(currentValue)) of \(formatted(targetValue)) \(displayedUnit)"
    }

    var targetLabel: String {
        formatted(targetValue)
    }

    var compactValueLabel: String {
        let displayedUnit = targetValue == 1 && unit == "hours" ? "hour" : unit
        return "\(formatted(currentValue)) of \(formatted(targetValue)) \(displayedUnit)"
    }

    var statusLabel: String {
        if progress >= 1 {
            return "Milestone unlocked"
        }
        if let earnedTarget {
            return "\(formatted(earnedTarget)) reached · next \(formatted(targetValue))"
        }
        return "Next at \(formatted(targetValue))"
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(1)))
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
            playImage: "repeat",
            playTitle: songPlayTitle,
            timeTitle: songTimeTitle
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
            playImage: "rectangle.stack.fill",
            playTitle: albumPlayTitle,
            timeTitle: albumTimeTitle
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
            playImage: "star.fill",
            playTitle: artistPlayTitle,
            timeTitle: artistTimeTitle
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
        playImage: String,
        playTitle: (Double) -> String,
        timeTitle: (Double) -> String
    ) -> [RecapMilestone] {
        let playProgress = progress(value: Double(playCount), thresholds: playThresholds)
        let listeningHours = listeningDuration / 3_600
        let timeProgress = progress(value: listeningHours, thresholds: timeThresholds)

        return [
            RecapMilestone(
                kind: playKind,
                title: playTitle(playProgress.target),
                detail: detail,
                systemImage: playImage,
                currentValue: Double(playCount),
                targetValue: playProgress.target,
                unit: "plays",
                earnedTarget: playProgress.earned,
                stage: playProgress.stage
            ),
            RecapMilestone(
                kind: timeKind,
                title: timeTitle(timeProgress.target),
                detail: detail,
                systemImage: "clock",
                currentValue: listeningHours,
                targetValue: timeProgress.target,
                unit: "hours",
                earnedTarget: timeProgress.earned,
                stage: timeProgress.stage
            )
        ]
    }

    private static func progress(value: Double, thresholds: [Double]) -> (target: Double, earned: Double?, stage: Int) {
        let targetIndex = thresholds.firstIndex { value < $0 } ?? max(thresholds.count - 1, 0)
        let earnedIndex = thresholds.lastIndex { value >= $0 }
        return (
            thresholds.indices.contains(targetIndex) ? thresholds[targetIndex] : max(value, 1),
            thresholds.last { value >= $0 },
            earnedIndex ?? 0
        )
    }

    private static func songPlayTitle(for _: Double) -> String { "Song on Repeat" }
    private static func songTimeTitle(for _: Double) -> String { "Song Devotion" }
    private static func albumPlayTitle(for _: Double) -> String { "Album in Rotation" }
    private static func albumTimeTitle(for _: Double) -> String { "Album Immersion" }
    private static func artistPlayTitle(for _: Double) -> String { "Artist Favorite" }
    private static func artistTimeTitle(for _: Double) -> String { "Artist Era" }
}

enum RecapMilestoneEngine {
    static func milestones(for recap: MonthlyRecap, periodName: String) -> [RecapMilestone] {
        var milestones: [RecapMilestone] = []

        let artistCount = recap.listenedArtistCount
        let artistProgress = progress(
            value: Double(artistCount),
            thresholds: [10, 25, 50, 100, 250, 500, 1_000]
        )
        milestones.append(
            RecapMilestone(
                kind: .artistDiscovery,
                title: artistDiscoveryTitle(for: artistProgress.target),
                detail: "Artists listened to in \(periodName)",
                systemImage: "person.2.wave.2.fill",
                currentValue: Double(artistCount),
                targetValue: artistProgress.target,
                unit: "artists",
                earnedTarget: artistProgress.earned,
                stage: artistProgress.stage
            )
        )

        let songProgress = progress(
            value: Double(recap.playedSongCount),
            thresholds: [25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
        )
        milestones.append(
            RecapMilestone(
                kind: .songDiscovery,
                title: songDiscoveryTitle(for: songProgress.target),
                detail: "Songs listened to in \(periodName)",
                systemImage: "music.note.list",
                currentValue: Double(recap.playedSongCount),
                targetValue: songProgress.target,
                unit: "songs",
                earnedTarget: songProgress.earned,
                stage: songProgress.stage
            )
        )

        let listeningHours = recap.totalListeningDuration / 3_600
        let listeningProgress = progress(
            value: listeningHours,
            thresholds: [5, 10, 25, 50, 100, 250, 500, 1_000, 2_500]
        )
        milestones.append(
            RecapMilestone(
                kind: .listeningTime,
                title: listeningTitle(for: listeningProgress.target),
                detail: "Total listening time in \(periodName)",
                systemImage: "headphones",
                currentValue: listeningHours,
                targetValue: listeningProgress.target,
                unit: "hours",
                earnedTarget: listeningProgress.earned,
                stage: listeningProgress.stage
            )
        )

        if let song = recap.topSongs.first {
            let hours = song.listeningDuration / 3_600
            let songProgress = progress(value: hours, thresholds: [1, 3, 6, 12, 24, 48, 100, 250])
            milestones.append(
                RecapMilestone(
                    kind: .songBond,
                    title: songBondTitle(for: songProgress.target),
                    detail: "Listening time for \(song.title) by \(song.artist)",
                    systemImage: "repeat",
                    currentValue: hours,
                    targetValue: songProgress.target,
                    unit: "hours",
                    earnedTarget: songProgress.earned,
                    stage: songProgress.stage
                )
            )
        }

        if let album = recap.topAlbums.first {
            let hours = album.listeningDuration / 3_600
            let albumProgress = progress(value: hours, thresholds: [2, 5, 10, 24, 50, 100, 250])
            milestones.append(
                RecapMilestone(
                    kind: .albumHome,
                    title: albumHomeTitle(for: albumProgress.target),
                    detail: "Listening time for \(album.title) by \(album.subtitle)",
                    systemImage: "rectangle.stack.fill",
                    currentValue: hours,
                    targetValue: albumProgress.target,
                    unit: "hours",
                    earnedTarget: albumProgress.earned,
                    stage: albumProgress.stage
                )
            )
        }

        if let artist = recap.topArtists.first {
            let hours = artist.listeningDuration / 3_600
            let artistProgress = progress(value: hours, thresholds: [5, 10, 25, 50, 100, 250, 500])
            milestones.append(
                RecapMilestone(
                    kind: .artistEra,
                    title: artistEraTitle(for: artistProgress.target),
                    detail: "Listening time for \(artist.title)",
                    systemImage: "star.fill",
                    currentValue: hours,
                    targetValue: artistProgress.target,
                    unit: "hours",
                    earnedTarget: artistProgress.earned,
                    stage: artistProgress.stage
                )
            )
        }

        return milestones
    }

    private static func progress(value: Double, thresholds: [Double]) -> (target: Double, earned: Double?, stage: Int) {
        let earned = thresholds.last { value >= $0 }
        let targetIndex = thresholds.firstIndex { value < $0 } ?? max(thresholds.count - 1, 0)
        let target = thresholds.indices.contains(targetIndex) ? thresholds[targetIndex] : max(value, 1)
        let earnedIndex = thresholds.lastIndex { value >= $0 }
        return (target, earned, earnedIndex ?? 0)
    }

    private static func artistDiscoveryTitle(for _: Double) -> String { "Artist Explorer" }
    private static func songDiscoveryTitle(for _: Double) -> String { "Song Explorer" }
    private static func listeningTitle(for _: Double) -> String { "Music Marathon" }
    private static func songBondTitle(for _: Double) -> String { "Song Devotion" }
    private static func albumHomeTitle(for _: Double) -> String { "Album Immersion" }
    private static func artistEraTitle(for _: Double) -> String { "Artist Era" }
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
