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

    static func empty(at date: Date = Date(), calendar: Calendar = .current) -> WeeklyRecapComparison {
        WeeklyRecapComparison(current: .empty(for: date, calendar: calendar), previous: nil)
    }
}

struct RecapMilestone: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case plays
        case listeningTime
        case song
        case album
        case artist
    }

    let kind: Kind
    let threshold: Int
    let title: String
    let detail: String
    let systemImage: String

    var id: String { "\(kind.rawValue)-\(threshold)-\(title)" }
}

enum RecapMilestoneEngine {
    static func earnedMilestones(for recap: MonthlyRecap, periodName: String) -> [RecapMilestone] {
        var milestones: [RecapMilestone] = []

        if let threshold = highestReached(recap.totalPlayDelta, thresholds: [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]) {
            milestones.append(
                RecapMilestone(
                    kind: .plays,
                    threshold: threshold,
                    title: "\(threshold.formatted()) plays",
                    detail: "Reached in \(periodName)",
                    systemImage: "play.fill"
                )
            )
        }

        let listeningHours = Int(recap.totalListeningDuration / 3_600)
        if let threshold = highestReached(listeningHours, thresholds: [5, 10, 25, 50, 100, 250, 500, 1_000]) {
            milestones.append(
                RecapMilestone(
                    kind: .listeningTime,
                    threshold: threshold,
                    title: "\(threshold.formatted()) listening hours",
                    detail: "Reached in \(periodName)",
                    systemImage: "clock.fill"
                )
            )
        }

        if let song = recap.topSongs.first,
           let threshold = highestReached(song.playDelta, thresholds: [10, 25, 50, 100, 250, 500, 1_000]) {
            milestones.append(
                RecapMilestone(
                    kind: .song,
                    threshold: threshold,
                    title: "\(threshold.formatted()) plays with \(song.title)",
                    detail: song.artist,
                    systemImage: "music.note"
                )
            )
        }

        if let album = recap.topAlbums.first,
           let threshold = highestReached(album.playDelta, thresholds: [25, 50, 100, 250, 500, 1_000]) {
            milestones.append(
                RecapMilestone(
                    kind: .album,
                    threshold: threshold,
                    title: "\(threshold.formatted()) plays from \(album.title)",
                    detail: album.subtitle,
                    systemImage: "rectangle.stack.fill"
                )
            )
        }

        if let artist = recap.topArtists.first,
           let threshold = highestReached(artist.playDelta, thresholds: [25, 50, 100, 250, 500, 1_000, 2_500]) {
            milestones.append(
                RecapMilestone(
                    kind: .artist,
                    threshold: threshold,
                    title: "\(threshold.formatted()) plays with \(artist.title)",
                    detail: periodName,
                    systemImage: "person.fill"
                )
            )
        }

        return milestones
    }

    private static func highestReached(_ value: Int, thresholds: [Int]) -> Int? {
        thresholds.last { value >= $0 }
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
            previous: previousBucket.map(insight(from:))
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
