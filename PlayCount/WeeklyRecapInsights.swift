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

    var id: String { kind.rawValue }

    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(max(currentValue / targetValue, 0), 1)
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
        return "\(formatted(currentValue)) / \(formatted(targetValue)) \(displayedUnit)"
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
            playImage: "star.circle.fill",
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
                earnedTarget: playProgress.earned
            ),
            RecapMilestone(
                kind: timeKind,
                title: timeTitle(timeProgress.target),
                detail: detail,
                systemImage: "clock.fill",
                currentValue: listeningHours,
                targetValue: timeProgress.target,
                unit: "hours",
                earnedTarget: timeProgress.earned
            )
        ]
    }

    private static func progress(value: Double, thresholds: [Double]) -> (target: Double, earned: Double?) {
        (
            thresholds.first { value < $0 } ?? thresholds.last ?? max(value, 1),
            thresholds.last { value >= $0 }
        )
    }

    private static func songPlayTitle(for target: Double) -> String {
        switch target {
        case ...10: "First Loop"
        case ...50: "On Repeat"
        case ...250: "Heavy Rotation"
        case ...1_000: "Personal Classic"
        default: "Forever Track"
        }
    }

    private static func songTimeTitle(for target: Double) -> String {
        switch target {
        case ...3: "Extended Listen"
        case ...12: "Soundtrack Moment"
        case ...24: "All-Day Anthem"
        case ...100: "Permanent Favorite"
        default: "A Life With One Song"
        }
    }

    private static func albumPlayTitle(for target: Double) -> String {
        switch target {
        case ...25: "First Spins"
        case ...100: "Front to Back"
        case ...500: "Album Resident"
        case ...2_500: "Permanent Rotation"
        default: "Desert Island Record"
        }
    }

    private static func albumTimeTitle(for target: Double) -> String {
        switch target {
        case ...5: "Liner Notes Level"
        case ...24: "A Day in This Album"
        case ...100: "Deep Album Era"
        default: "Second Home"
        }
    }

    private static func artistPlayTitle(for target: Double) -> String {
        switch target {
        case ...100: "Fan in the Making"
        case ...500: "Inner Circle"
        case ...2_500: "Full Artist Era"
        default: "Forever Fan"
        }
    }

    private static func artistTimeTitle(for target: Double) -> String {
        switch target {
        case ...10: "Getting Acquainted"
        case ...50: "Discography Dweller"
        case ...250: "Superfan Hours"
        default: "Lifetime Artist"
        }
    }
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
                detail: "Artists heard in \(periodName)",
                systemImage: "person.2.wave.2.fill",
                currentValue: Double(artistCount),
                targetValue: artistProgress.target,
                unit: "artists",
                earnedTarget: artistProgress.earned
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
                detail: "Different songs in \(periodName)",
                systemImage: "music.note.list",
                currentValue: Double(recap.playedSongCount),
                targetValue: songProgress.target,
                unit: "songs",
                earnedTarget: songProgress.earned
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
                detail: "Your soundtrack for \(periodName)",
                systemImage: "headphones",
                currentValue: listeningHours,
                targetValue: listeningProgress.target,
                unit: "hours",
                earnedTarget: listeningProgress.earned
            )
        )

        if let song = recap.topSongs.first {
            let hours = song.listeningDuration / 3_600
            let songProgress = progress(value: hours, thresholds: [1, 3, 6, 12, 24, 48, 100, 250])
            milestones.append(
                RecapMilestone(
                    kind: .songBond,
                    title: songBondTitle(for: songProgress.target),
                    detail: "With \(song.title) by \(song.artist)",
                    systemImage: "repeat",
                    currentValue: hours,
                    targetValue: songProgress.target,
                    unit: "hours",
                    earnedTarget: songProgress.earned
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
                    detail: "Inside \(album.title) by \(album.subtitle)",
                    systemImage: "rectangle.stack.fill",
                    currentValue: hours,
                    targetValue: albumProgress.target,
                    unit: "hours",
                    earnedTarget: albumProgress.earned
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
                    detail: "In your \(artist.title) era",
                    systemImage: "star.circle.fill",
                    currentValue: hours,
                    targetValue: artistProgress.target,
                    unit: "hours",
                    earnedTarget: artistProgress.earned
                )
            )
        }

        return milestones
    }

    private static func progress(value: Double, thresholds: [Double]) -> (target: Double, earned: Double?) {
        let earned = thresholds.last { value >= $0 }
        let target = thresholds.first { value < $0 } ?? thresholds.last ?? max(value, 1)
        return (target, earned)
    }

    private static func artistDiscoveryTitle(for target: Double) -> String {
        switch target {
        case ...10: "Open Ears"
        case ...25: "Sound Scout"
        case ...50: "Scene Hopper"
        case ...100: "Musical Atlas"
        case ...250: "Genre Voyager"
        case ...500: "World Tour"
        default: "Human Festival"
        }
    }

    private static func songDiscoveryTitle(for target: Double) -> String {
        switch target {
        case ...25: "Starter Mixtape"
        case ...50: "Mixtape Maker"
        case ...100: "The Songbook"
        case ...250: "Deep Catalog"
        case ...500: "Living Library"
        case ...1_000: "Human Jukebox"
        default: "Endless Queue"
        }
    }

    private static func listeningTitle(for target: Double) -> String {
        switch target {
        case ...5: "Long Play"
        case ...10: "Soundtrack Mode"
        case ...25: "Around the Clock"
        case ...50: "Audio Orbit"
        case ...100: "Permanent Headphones"
        default: "A Life in Sound"
        }
    }

    private static func songBondTitle(for target: Double) -> String {
        switch target {
        case ...1: "On Repeat"
        case ...3: "Extended Cut"
        case ...6: "All-Day Loop"
        case ...12: "Half-Day Anthem"
        case ...24: "A Day With One Song"
        case ...48: "Two-Day Obsession"
        default: "Forever Track"
        }
    }

    private static func albumHomeTitle(for target: Double) -> String {
        switch target {
        case ...2: "Front to Back"
        case ...5: "Liner Notes Level"
        case ...10: "Album Resident"
        case ...24: "A Day Inside an Album"
        default: "Permanent Rotation"
        }
    }

    private static func artistEraTitle(for target: Double) -> String {
        switch target {
        case ...5: "Fan in the Making"
        case ...10: "Inner Circle"
        case ...25: "Full Artist Era"
        case ...50: "Discography Dweller"
        default: "Forever Fan"
        }
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
