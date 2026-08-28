import Foundation
@preconcurrency import MediaPlayer
import Security
import SQLite3
import UIKit

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

struct MonthlyRecap: Equatable, @unchecked Sendable {
    struct RankedSong: Identifiable, Equatable {
        let id: UInt64
        let title: String
        let artist: String
        let albumTitle: String
        let playDelta: Int
        let skipDelta: Int
        let listeningDuration: TimeInterval
        let artwork: MPMediaItemArtwork?
        let recordingIdentity: String?
        let playbackStoreID: String?

        init(
            id: UInt64,
            title: String,
            artist: String,
            albumTitle: String,
            playDelta: Int,
            skipDelta: Int,
            listeningDuration: TimeInterval,
            artwork: MPMediaItemArtwork?,
            recordingIdentity: String? = nil,
            playbackStoreID: String? = nil
        ) {
            self.id = id
            self.title = title
            self.artist = artist
            self.albumTitle = albumTitle
            self.playDelta = playDelta
            self.skipDelta = skipDelta
            self.listeningDuration = listeningDuration
            self.artwork = artwork
            self.recordingIdentity = recordingIdentity
            self.playbackStoreID = playbackStoreID
        }

        static func == (lhs: RankedSong, rhs: RankedSong) -> Bool {
            lhs.id == rhs.id &&
                lhs.title == rhs.title &&
                lhs.artist == rhs.artist &&
                lhs.albumTitle == rhs.albumTitle &&
                lhs.playDelta == rhs.playDelta &&
                lhs.skipDelta == rhs.skipDelta &&
                lhs.listeningDuration == rhs.listeningDuration &&
                lhs.recordingIdentity == rhs.recordingIdentity &&
                lhs.playbackStoreID == rhs.playbackStoreID
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

    struct MovementGroup: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let playDelta: Int
        let rankChange: Int
        let currentRank: Int
        let previousRank: Int?
        let artwork: MPMediaItemArtwork?

        static func == (lhs: MovementGroup, rhs: MovementGroup) -> Bool {
            lhs.id == rhs.id &&
                lhs.title == rhs.title &&
                lhs.subtitle == rhs.subtitle &&
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
    let listenedArtistCount: Int
    let newSongCount: Int
    let topSongs: [RankedSong]
    let topArtists: [RankedGroup]
    let topAlbums: [RankedGroup]
    let biggestGainers: [MovementSong]
    let biggestAlbumGainers: [MovementGroup]
    let biggestArtistGainers: [MovementGroup]
    let topNewSongs: [RankedSong]
    let unattributedPlayDelta: Int
    let unattributedListeningDuration: TimeInterval

    init(
        monthStart: Date,
        generatedAt: Date,
        lastCaptureReason: RecapSnapshotReason?,
        trackingStart: Date?,
        snapshotCount: Int,
        totalPlayDelta: Int,
        totalSkipDelta: Int,
        totalListeningDuration: TimeInterval,
        playedSongCount: Int,
        listenedArtistCount: Int? = nil,
        newSongCount: Int,
        topSongs: [RankedSong],
        topArtists: [RankedGroup],
        topAlbums: [RankedGroup],
        biggestGainers: [MovementSong],
        biggestAlbumGainers: [MovementGroup] = [],
        biggestArtistGainers: [MovementGroup] = [],
        topNewSongs: [RankedSong],
        unattributedPlayDelta: Int = 0,
        unattributedListeningDuration: TimeInterval = 0
    ) {
        self.monthStart = monthStart
        self.generatedAt = generatedAt
        self.lastCaptureReason = lastCaptureReason
        self.trackingStart = trackingStart
        self.snapshotCount = snapshotCount
        self.totalPlayDelta = totalPlayDelta
        self.totalSkipDelta = totalSkipDelta
        self.totalListeningDuration = totalListeningDuration
        self.playedSongCount = playedSongCount
        self.listenedArtistCount = listenedArtistCount ?? topArtists.filter { $0.playDelta > 0 }.count
        self.newSongCount = newSongCount
        self.topSongs = topSongs
        self.topArtists = topArtists
        self.topAlbums = topAlbums
        self.biggestGainers = biggestGainers
        self.biggestAlbumGainers = biggestAlbumGainers
        self.biggestArtistGainers = biggestArtistGainers
        self.topNewSongs = topNewSongs
        self.unattributedPlayDelta = unattributedPlayDelta
        self.unattributedListeningDuration = unattributedListeningDuration
    }

    fileprivate func replacingMonthStart(_ monthStart: Date) -> MonthlyRecap {
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
            listenedArtistCount: listenedArtistCount,
            newSongCount: newSongCount,
            topSongs: topSongs,
            topArtists: topArtists,
            topAlbums: topAlbums,
            biggestGainers: biggestGainers,
            biggestAlbumGainers: biggestAlbumGainers,
            biggestArtistGainers: biggestArtistGainers,
            topNewSongs: topNewSongs,
            unattributedPlayDelta: unattributedPlayDelta,
            unattributedListeningDuration: unattributedListeningDuration
        )
    }

    fileprivate func rebased(at date: Date, reason: RecapSnapshotReason?) -> MonthlyRecap {
        MonthlyRecap(
            monthStart: monthStart,
            generatedAt: date,
            lastCaptureReason: reason,
            trackingStart: trackingStart,
            snapshotCount: snapshotCount + 1,
            totalPlayDelta: totalPlayDelta,
            totalSkipDelta: totalSkipDelta,
            totalListeningDuration: totalListeningDuration,
            playedSongCount: playedSongCount,
            listenedArtistCount: listenedArtistCount,
            newSongCount: newSongCount,
            topSongs: topSongs,
            topArtists: topArtists,
            topAlbums: topAlbums,
            biggestGainers: biggestGainers,
            biggestAlbumGainers: biggestAlbumGainers,
            biggestArtistGainers: biggestArtistGainers,
            topNewSongs: topNewSongs,
            unattributedPlayDelta: unattributedPlayDelta,
            unattributedListeningDuration: unattributedListeningDuration
        )
    }

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
            listenedArtistCount: 0,
            newSongCount: 0,
            topSongs: [],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            biggestAlbumGainers: [],
            biggestArtistGainers: [],
            topNewSongs: [],
            unattributedPlayDelta: 0,
            unattributedListeningDuration: 0
        )
    }
}

struct CachedRecapPresentation: @unchecked Sendable {
    let monthlyRecaps: [MonthlyRecap]
    let yearlyRecaps: [Int: MonthlyRecap]
    let availableMonthStarts: [Date]

    static let empty = CachedRecapPresentation(
        monthlyRecaps: [],
        yearlyRecaps: [:],
        availableMonthStarts: []
    )
}

struct RecapSnapshotSyncPayload: Codable, Equatable, Identifiable {
    let id: String
    let capturedAt: Date
    let counterSignature: String
    let reliabilityPolicyVersion: Int?
    let archiveReliabilityPolicyVersion: Int?
    let encodedSnapshot: Data
    let encodedRecaps: Data?
    let encodedYearlyRecaps: Data?
    let encodedUnattributedIntervals: Data?

    init(
        id: String,
        capturedAt: Date,
        counterSignature: String,
        reliabilityPolicyVersion: Int? = nil,
        archiveReliabilityPolicyVersion: Int? = nil,
        encodedSnapshot: Data,
        encodedRecaps: Data? = nil,
        encodedYearlyRecaps: Data? = nil,
        encodedUnattributedIntervals: Data? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.counterSignature = counterSignature
        self.reliabilityPolicyVersion = reliabilityPolicyVersion
        self.archiveReliabilityPolicyVersion = archiveReliabilityPolicyVersion
        self.encodedSnapshot = encodedSnapshot
        self.encodedRecaps = encodedRecaps
        self.encodedYearlyRecaps = encodedYearlyRecaps
        self.encodedUnattributedIntervals = encodedUnattributedIntervals
    }
}

extension RecapSnapshotSyncPayload {
    static let manifestArchiveOnlyID = "__playcount_manifest_archive__"

    var isManifestArchiveOnly: Bool {
        id == Self.manifestArchiveOnlyID
    }
}

struct RecapArchiveEvidenceData: Equatable {
    let encodedRecaps: Data?
    let encodedYearlyRecaps: Data?
    let encodedUnattributedIntervals: Data?
    let minimumReliabilityPolicyVersion: Int?
}

struct RecapReliabilityStatus: Equatable {
    let lastTrustedUpdate: Date?
    let lastRejectedObservation: Date?
    let recentRejectedObservationCount: Int

    static let empty = RecapReliabilityStatus(
        lastTrustedUpdate: nil,
        lastRejectedObservation: nil,
        recentRejectedObservationCount: 0
    )

    var isUsingLastReliableUpdate: Bool {
        guard let lastRejectedObservation else { return false }
        guard let lastTrustedUpdate else { return true }
        return lastRejectedObservation > lastTrustedUpdate
    }
}

struct RecapDiagnosticMonth: Equatable, Identifiable, Sendable {
    let monthStart: Date
    let totalPlayDelta: Int
    let totalListeningDuration: TimeInterval
    let recapSnapshotCount: Int
    let storedSnapshotCount: Int
    let trackingStart: Date?
    let generatedAt: Date
    let unattributedPlayDelta: Int
    let reliabilityPolicyVersion: Int
    let isCanonicalMonthIdentity: Bool

    var id: Date { monthStart }

    var sourceDescription: String {
        storedSnapshotCount > 0 ? "\(storedSnapshotCount) local snapshots" : "Synced monthly summary"
    }
}

struct RecapDiagnosticsReport: Equatable, Sendable {
    let generatedAt: Date
    let appVersion: String
    let buildNumber: String
    let reliabilityPolicyVersion: Int
    let totalStoredSnapshots: Int
    let monthlyLedgerCount: Int
    let cloudSummaryCount: Int
    let duplicateMonthCount: Int
    let yearlyTotalsMatchMonthlyLedgers: Bool
    let unattributedIntervalCount: Int
    let unattributedPlayDelta: Int
    let lastTrustedUpdate: Date?
    let lastRejectedObservation: Date?
    let recentRejectedObservationCount: Int
    let months: [RecapDiagnosticMonth]

    var hasCanonicalMonthLedger: Bool {
        duplicateMonthCount == 0 && months.allSatisfy(\.isCanonicalMonthIdentity)
    }

    var exportText: String {
        let monthLines = months.map { month in
            let tracking = month.trackingStart?.formatted(date: .numeric, time: .shortened) ?? "unknown"
            return """
            \(month.monthStart.formatted(.dateTime.year().month(.wide))): plays=\(month.totalPlayDelta), minutes=\(Int((month.totalListeningDuration / 60).rounded())), recapSnapshots=\(month.recapSnapshotCount), storedSnapshots=\(month.storedSnapshotCount), trackingStart=\(tracking), generated=\(month.generatedAt.formatted(date: .numeric, time: .shortened)), unattributedPlays=\(month.unattributedPlayDelta), policy=\(month.reliabilityPolicyVersion), canonicalMonth=\(month.isCanonicalMonthIdentity)
            """
        }.joined(separator: "\n")

        return """
        PlayCount Recap Diagnostics
        App: \(appVersion) (\(buildNumber))
        Generated: \(generatedAt.formatted(date: .numeric, time: .standard))
        Reliability policy: \(reliabilityPolicyVersion)
        Stored snapshots: \(totalStoredSnapshots)
        Monthly ledgers: \(monthlyLedgerCount)
        Cloud summaries: \(cloudSummaryCount)
        Duplicate logical months: \(duplicateMonthCount)
        Canonical month identities: \(hasCanonicalMonthLedger)
        Yearly totals match monthly ledgers: \(yearlyTotalsMatchMonthlyLedgers)
        Unattributed intervals: \(unattributedIntervalCount)
        Unattributed plays: \(unattributedPlayDelta)
        Last trusted update: \(lastTrustedUpdate?.formatted(date: .numeric, time: .standard) ?? "none")
        Last rejected observation: \(lastRejectedObservation?.formatted(date: .numeric, time: .standard) ?? "none")
        Recent rejected observations: \(recentRejectedObservationCount)

        Monthly coverage
        \(monthLines.isEmpty ? "No monthly ledgers" : monthLines)
        """
    }
}

struct YearlyRecapMonthlyHighlight: Identifiable, Equatable {
    let month: Date
    let recap: MonthlyRecap

    var id: Date { month }
}

private func normalizedRecapIdentityComponent(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .lowercased()
}

private func legacyRecapRecordingIdentity(
    title: String,
    artist: String,
    albumTitle: String
) -> String {
    [
        "recording",
        normalizedRecapIdentityComponent(title),
        normalizedRecapIdentityComponent(artist),
        normalizedRecapIdentityComponent(albumTitle)
    ].joined(separator: ":")
}

extension MonthlyRecap {
    static func yearly(
        for year: Int,
        months: [Date],
        monthlyRecaps: [MonthlyRecap],
        fallbackMonth: Date,
        fallbackRecap: MonthlyRecap
    ) -> MonthlyRecap {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Calendar.current.timeZone
        guard let firstMonth = months.first else {
            return fallbackRecap
        }

        let monthStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? fallbackMonth
        let orderedMonthlyRecaps = monthlyRecaps.sorted {
            if $0.monthStart == $1.monthStart {
                return $0.generatedAt < $1.generatedAt
            }
            return $0.monthStart < $1.monthStart
        }

        let allSongs = orderedMonthlyRecaps.flatMap { $0.topSongs + $0.topNewSongs }
        let identitiesByLegacyKey = Dictionary(grouping: allSongs.compactMap { song -> (String, String)? in
            guard let identity = song.recordingIdentity else { return nil }
            return (
                legacyRecapRecordingIdentity(
                    title: song.title,
                    artist: song.artist,
                    albumTitle: song.albumTitle
                ),
                identity
            )
        }, by: { $0.0 }).mapValues { Set($0.map { $0.1 }) }

        func yearlySongKey(_ song: RankedSong) -> String {
            if let identity = song.recordingIdentity {
                return identity
            }

            let legacyKey = legacyRecapRecordingIdentity(
                title: song.title,
                artist: song.artist,
                albumTitle: song.albumTitle
            )
            if let identities = identitiesByLegacyKey[legacyKey], identities.count == 1,
               let identity = identities.first {
                return identity
            }
            return legacyKey
        }

        func yearlyArtistKey(_ group: RankedGroup) -> String {
            "artist:\(normalizedRecapIdentityComponent(group.title))"
        }

        func yearlyAlbumKey(_ group: RankedGroup) -> String {
            [
                "album",
                normalizedRecapIdentityComponent(group.title),
                normalizedRecapIdentityComponent(group.subtitle)
            ].joined(separator: ":")
        }

        var songs: [String: RankedSongAggregate] = [:]
        var albums: [String: RankedGroupAggregate] = [:]
        var artists: [String: RankedGroupAggregate] = [:]
        var movement: [UInt64: MovementSongAggregate] = [:]
        var albumMovement: [String: MovementGroupAggregate] = [:]
        var artistMovement: [String: MovementGroupAggregate] = [:]
        var newSongIDs: [String] = []
        var newSongIDSet: Set<String> = []

        for recap in orderedMonthlyRecaps {
            var mergedSongIDsForMonth: Set<String> = []

            for song in recap.topSongs {
                let key = yearlySongKey(song)
                songs[key, default: RankedSongAggregate(song: song)].merge(song)
                mergedSongIDsForMonth.insert(key)
            }

            for song in recap.topNewSongs {
                let key = yearlySongKey(song)
                if !mergedSongIDsForMonth.contains(key) {
                    songs[key, default: RankedSongAggregate(song: song)].merge(song)
                    mergedSongIDsForMonth.insert(key)
                }
                if newSongIDSet.insert(key).inserted {
                    newSongIDs.append(key)
                }
            }

            for group in recap.topAlbums {
                let key = yearlyAlbumKey(group)
                albums[key, default: RankedGroupAggregate(group: group)].merge(group)
            }
            for group in recap.topArtists {
                let key = yearlyArtistKey(group)
                artists[key, default: RankedGroupAggregate(group: group)].merge(group)
            }
            for song in recap.biggestGainers {
                movement[song.id, default: MovementSongAggregate(song: song)].merge(song)
            }
            for group in recap.biggestAlbumGainers {
                let key = [
                    "album",
                    normalizedRecapIdentityComponent(group.title),
                    normalizedRecapIdentityComponent(group.subtitle)
                ].joined(separator: ":")
                albumMovement[key, default: MovementGroupAggregate(group: group)].merge(group)
            }
            for group in recap.biggestArtistGainers {
                let key = "artist:\(normalizedRecapIdentityComponent(group.title))"
                artistMovement[key, default: MovementGroupAggregate(group: group)].merge(group)
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

        let biggestAlbumGainers = albumMovement.values
            .map(\.movementGroup)
            .sorted(by: Self.movementGroupSort)

        let biggestArtistGainers = artistMovement.values
            .map(\.movementGroup)
            .sorted(by: Self.movementGroupSort)

        let newSongs = newSongIDs.compactMap { key in
            songs[key]?.rankedSong
        }
        .sorted { $0.playDelta > $1.playDelta }

        return MonthlyRecap(
            monthStart: monthStart,
            generatedAt: orderedMonthlyRecaps.map(\.generatedAt).max() ?? Date(),
            lastCaptureReason: orderedMonthlyRecaps.last?.lastCaptureReason,
            trackingStart: orderedMonthlyRecaps.compactMap(\.trackingStart).min() ?? firstMonth,
            snapshotCount: orderedMonthlyRecaps.reduce(0) { $0 + $1.snapshotCount },
            totalPlayDelta: orderedMonthlyRecaps.reduce(0) { $0 + $1.totalPlayDelta },
            totalSkipDelta: orderedMonthlyRecaps.reduce(0) { $0 + $1.totalSkipDelta },
            totalListeningDuration: orderedMonthlyRecaps.reduce(0) { $0 + $1.totalListeningDuration },
            playedSongCount: songs.count,
            newSongCount: orderedMonthlyRecaps.reduce(0) { $0 + $1.newSongCount },
            topSongs: rankedSongs,
            topArtists: rankedArtists,
            topAlbums: rankedAlbums,
            biggestGainers: biggestGainers,
            biggestAlbumGainers: biggestAlbumGainers,
            biggestArtistGainers: biggestArtistGainers,
            topNewSongs: newSongs,
            unattributedPlayDelta: orderedMonthlyRecaps.reduce(0) { $0 + $1.unattributedPlayDelta },
            unattributedListeningDuration: orderedMonthlyRecaps.reduce(0) {
                $0 + $1.unattributedListeningDuration
            }
        )
    }

    private struct RankedSongAggregate {
        var id: UInt64
        var title: String
        var artist: String
        var albumTitle: String
        var artwork: MPMediaItemArtwork?
        var recordingIdentity: String?
        var playbackStoreID: String?
        var playDelta: Int
        var skipDelta: Int
        var listeningDuration: TimeInterval

        init(song: MonthlyRecap.RankedSong) {
            id = song.id
            title = song.title
            artist = song.artist
            albumTitle = song.albumTitle
            artwork = song.artwork
            recordingIdentity = song.recordingIdentity
            playbackStoreID = song.playbackStoreID
            playDelta = 0
            skipDelta = 0
            listeningDuration = 0
        }

        mutating func merge(_ song: MonthlyRecap.RankedSong) {
            playDelta += song.playDelta
            skipDelta += song.skipDelta
            listeningDuration += song.listeningDuration
            id = song.id
            title = song.title
            artist = song.artist
            albumTitle = song.albumTitle
            artwork = song.artwork ?? artwork
            recordingIdentity = song.recordingIdentity ?? recordingIdentity
            playbackStoreID = song.playbackStoreID ?? playbackStoreID
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
                artwork: artwork,
                recordingIdentity: recordingIdentity,
                playbackStoreID: playbackStoreID
            )
        }
    }

    private struct RankedGroupAggregate {
        var id: String
        var title: String
        var subtitle: String
        var artwork: MPMediaItemArtwork?
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
            id = group.id
            title = group.title
            subtitle = group.subtitle
            artwork = group.artwork ?? artwork
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

    private struct MovementGroupAggregate {
        var id: String
        var title: String
        var subtitle: String
        var playDelta: Int
        var rankChange: Int
        var currentRank: Int
        var previousRank: Int?
        var artwork: MPMediaItemArtwork?

        init(group: MonthlyRecap.MovementGroup) {
            id = group.id
            title = group.title
            subtitle = group.subtitle
            playDelta = 0
            rankChange = 0
            currentRank = group.currentRank
            previousRank = group.previousRank
            artwork = group.artwork
        }

        mutating func merge(_ group: MonthlyRecap.MovementGroup) {
            playDelta += group.playDelta
            rankChange = max(rankChange, group.rankChange)
            id = group.id
            title = group.title
            subtitle = group.subtitle
            currentRank = group.currentRank
            previousRank = group.previousRank
            artwork = group.artwork ?? artwork
        }

        var movementGroup: MonthlyRecap.MovementGroup {
            MonthlyRecap.MovementGroup(
                id: id,
                title: title,
                subtitle: subtitle,
                playDelta: playDelta,
                rankChange: rankChange,
                currentRank: currentRank,
                previousRank: previousRank,
                artwork: artwork
            )
        }
    }

    private static func movementGroupSort(
        _ lhs: MonthlyRecap.MovementGroup,
        _ rhs: MonthlyRecap.MovementGroup
    ) -> Bool {
        if lhs.rankChange != rhs.rankChange { return lhs.rankChange > rhs.rankChange }
        if lhs.playDelta != rhs.playDelta { return lhs.playDelta > rhs.playDelta }
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.subtitle.localizedCaseInsensitiveCompare(rhs.subtitle) == .orderedAscending
    }
}

final class MonthlyRecapSnapshotStore {
    fileprivate static let maxSyncPayloadBytes = 250_000
    fileprivate static let minSyncedSongCount = 100
    private static let currentGapPolicyVersion = 1
    // Version 3 makes the CAS-protected Cloud manifest authoritative for recap
    // summaries. That lets corrected lower totals outrank stale v2 archives.
    fileprivate static let currentCounterReliabilityPolicyVersion = 3
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
        let encodedUnattributedIntervals: Data?

        init(
            capturedAt: Date,
            reason: RecapSnapshotReason?,
            appVersion: String?,
            scannedSongCount: Int?,
            deviceIdentifier: String?,
            aggregateCounters: AggregateCounters? = nil,
            songs: [SongSnapshot],
            encodedUnattributedIntervals: Data? = nil
        ) {
            self.capturedAt = capturedAt
            self.reason = reason
            self.appVersion = appVersion
            self.scannedSongCount = scannedSongCount
            self.deviceIdentifier = deviceIdentifier
            self.aggregateCounters = aggregateCounters
            self.songs = songs
            self.encodedUnattributedIntervals = encodedUnattributedIntervals
        }
    }

    fileprivate struct SongSnapshot: Codable, Equatable {
        let id: UInt64
        let title: String
        let artist: String
        let albumTitle: String
        let albumArtist: String
        let playCount: Int
        let skipCount: Int
        let playbackDuration: TimeInterval
        let lastPlayedDate: Date?
        let dateAdded: Date?
        let albumPersistentID: UInt64
        let artistPersistentID: UInt64
        let playbackStoreID: String?

        init(
            id: UInt64,
            title: String,
            artist: String,
            albumTitle: String,
            albumArtist: String? = nil,
            playCount: Int,
            skipCount: Int,
            playbackDuration: TimeInterval,
            lastPlayedDate: Date?,
            dateAdded: Date?,
            albumPersistentID: UInt64,
            artistPersistentID: UInt64,
            playbackStoreID: String? = nil
        ) {
            self.id = id
            self.title = title
            self.artist = artist
            self.albumTitle = albumTitle
            self.albumArtist = albumArtist?.nonEmptyFallback(artist) ?? artist
            self.playCount = playCount
            self.skipCount = skipCount
            self.playbackDuration = playbackDuration
            self.lastPlayedDate = lastPlayedDate
            self.dateAdded = dateAdded
            self.albumPersistentID = albumPersistentID
            self.artistPersistentID = artistPersistentID
            let normalizedPlaybackStoreID = playbackStoreID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.playbackStoreID = normalizedPlaybackStoreID?.isEmpty == false
                ? normalizedPlaybackStoreID
                : nil
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let artist = try container.decode(String.self, forKey: .artist)
            self.init(
                id: try container.decode(UInt64.self, forKey: .id),
                title: try container.decode(String.self, forKey: .title),
                artist: artist,
                albumTitle: try container.decode(String.self, forKey: .albumTitle),
                albumArtist: try container.decodeIfPresent(String.self, forKey: .albumArtist) ?? artist,
                playCount: try container.decode(Int.self, forKey: .playCount),
                skipCount: try container.decode(Int.self, forKey: .skipCount),
                playbackDuration: try container.decode(TimeInterval.self, forKey: .playbackDuration),
                lastPlayedDate: try container.decodeIfPresent(Date.self, forKey: .lastPlayedDate),
                dateAdded: try container.decodeIfPresent(Date.self, forKey: .dateAdded),
                albumPersistentID: try container.decode(UInt64.self, forKey: .albumPersistentID),
                artistPersistentID: try container.decode(UInt64.self, forKey: .artistPersistentID),
                playbackStoreID: try container.decodeIfPresent(String.self, forKey: .playbackStoreID)
            )
        }
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
            let recordingIdentity: String?
            let playbackStoreID: String?
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

        struct MovementGroup: Codable, Equatable {
            let id: String
            let title: String
            let subtitle: String
            let playDelta: Int
            let rankChange: Int
            let currentRank: Int
            let previousRank: Int?
        }

        let monthStart: Date
        let generatedAt: Date
        let reliabilityPolicyVersion: Int?
        let lastCaptureReason: RecapSnapshotReason?
        let trackingStart: Date?
        let snapshotCount: Int
        let totalPlayDelta: Int
        let totalSkipDelta: Int
        let totalListeningDuration: TimeInterval
        let playedSongCount: Int
        let listenedArtistCount: Int?
        let newSongCount: Int
        let topSongs: [RankedSong]
        let topArtists: [RankedGroup]
        let topAlbums: [RankedGroup]
        let biggestGainers: [MovementSong]
        let biggestAlbumGainers: [MovementGroup]?
        let biggestArtistGainers: [MovementGroup]?
        let topNewSongs: [RankedSong]
        let unattributedPlayDelta: Int?
        let unattributedListeningDuration: TimeInterval?

        var id: Date { monthStart }

        var rankedEvidenceCount: Int {
            topSongs.count + topArtists.count + topAlbums.count + biggestGainers.count +
                (biggestAlbumGainers?.count ?? 0) + (biggestArtistGainers?.count ?? 0) + topNewSongs.count
        }

        var rankingFingerprint: String {
            let songs = topSongs.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            let artists = topArtists.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            let albums = topAlbums.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            let gainers = biggestGainers.map { "\($0.id):\($0.playDelta):\($0.rankChange)" }.joined(separator: ",")
            let albumGainers = (biggestAlbumGainers ?? []).map { "\($0.id):\($0.playDelta):\($0.rankChange)" }.joined(separator: ",")
            let artistGainers = (biggestArtistGainers ?? []).map { "\($0.id):\($0.playDelta):\($0.rankChange)" }.joined(separator: ",")
            let newSongs = topNewSongs.map { "\($0.id):\($0.playDelta)" }.joined(separator: ",")
            return [songs, artists, albums, gainers, albumGainers, artistGainers, newSongs].joined(separator: "|")
        }

        var hasActivity: Bool {
            totalPlayDelta > 0 || newSongCount > 0
        }

        var hasRankingEvidence: Bool {
            totalPlayDelta == 0 || !topSongs.isEmpty || !topArtists.isEmpty || !topAlbums.isEmpty
        }

        init(
            recap: MonthlyRecap,
            preservingAllRankings: Bool = false,
            reliabilityPolicyVersion: Int? = MonthlyRecapSnapshotStore.currentCounterReliabilityPolicyVersion
        ) {
            monthStart = recap.monthStart
            generatedAt = recap.generatedAt
            self.reliabilityPolicyVersion = reliabilityPolicyVersion
            lastCaptureReason = recap.lastCaptureReason
            trackingStart = recap.trackingStart
            snapshotCount = recap.snapshotCount
            totalPlayDelta = recap.totalPlayDelta
            totalSkipDelta = recap.totalSkipDelta
            totalListeningDuration = recap.totalListeningDuration
            playedSongCount = recap.playedSongCount
            listenedArtistCount = recap.listenedArtistCount
            newSongCount = recap.newSongCount
            let rankedSongs = preservingAllRankings
                ? Array(recap.topSongs[...])
                : Array(recap.topSongs.prefix(MonthlyRecapSnapshotStore.maxSyncedRecapRankedSongCount))
            let rankedGroupsLimit = preservingAllRankings ? Int.max : MonthlyRecapSnapshotStore.maxSyncedRecapRankedGroupCount
            let movementLimit = preservingAllRankings ? Int.max : MonthlyRecapSnapshotStore.maxSyncedRecapMovementSongCount
            let newSongsLimit = preservingAllRankings ? Int.max : MonthlyRecapSnapshotStore.maxSyncedRecapRankedSongCount
            topSongs = rankedSongs.map {
                RankedSong(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    albumTitle: $0.albumTitle,
                    playDelta: $0.playDelta,
                    skipDelta: $0.skipDelta,
                    listeningDuration: $0.listeningDuration,
                    recordingIdentity: $0.recordingIdentity,
                    playbackStoreID: $0.playbackStoreID
                )
            }
            topArtists = recap.topArtists.prefix(rankedGroupsLimit).map {
                RankedGroup(
                    id: $0.id,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    playDelta: $0.playDelta,
                    listeningDuration: $0.listeningDuration
                )
            }
            topAlbums = recap.topAlbums.prefix(rankedGroupsLimit).map {
                RankedGroup(
                    id: $0.id,
                    title: $0.title,
                    subtitle: $0.subtitle,
                    playDelta: $0.playDelta,
                    listeningDuration: $0.listeningDuration
                )
            }
            biggestGainers = recap.biggestGainers.prefix(movementLimit).map {
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
            biggestAlbumGainers = recap.biggestAlbumGainers.prefix(movementLimit).map {
                MovementGroup(id: $0.id, title: $0.title, subtitle: $0.subtitle, playDelta: $0.playDelta,
                              rankChange: $0.rankChange, currentRank: $0.currentRank, previousRank: $0.previousRank)
            }
            biggestArtistGainers = recap.biggestArtistGainers.prefix(movementLimit).map {
                MovementGroup(id: $0.id, title: $0.title, subtitle: $0.subtitle, playDelta: $0.playDelta,
                              rankChange: $0.rankChange, currentRank: $0.currentRank, previousRank: $0.previousRank)
            }
            topNewSongs = recap.topNewSongs.prefix(newSongsLimit).map {
                RankedSong(
                    id: $0.id,
                    title: $0.title,
                    artist: $0.artist,
                    albumTitle: $0.albumTitle,
                    playDelta: $0.playDelta,
                    skipDelta: $0.skipDelta,
                    listeningDuration: $0.listeningDuration,
                    recordingIdentity: $0.recordingIdentity,
                    playbackStoreID: $0.playbackStoreID
                )
            }
            unattributedPlayDelta = recap.unattributedPlayDelta
            unattributedListeningDuration = recap.unattributedListeningDuration
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
                listenedArtistCount: listenedArtistCount,
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
                        artwork: artworkLookup.songs[$0.id],
                        recordingIdentity: $0.recordingIdentity,
                        playbackStoreID: $0.playbackStoreID
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
                biggestAlbumGainers: (biggestAlbumGainers ?? []).map {
                    MonthlyRecap.MovementGroup(
                        id: $0.id, title: $0.title, subtitle: $0.subtitle, playDelta: $0.playDelta,
                        rankChange: $0.rankChange, currentRank: $0.currentRank, previousRank: $0.previousRank,
                        artwork: artworkLookup.albums[UInt64($0.id) ?? 0] ?? artworkLookup.albumsByName[ArtworkLookup.albumKey(title: $0.title, artist: $0.subtitle)]
                    )
                },
                biggestArtistGainers: (biggestArtistGainers ?? []).map {
                    MonthlyRecap.MovementGroup(
                        id: $0.id, title: $0.title, subtitle: $0.subtitle, playDelta: $0.playDelta,
                        rankChange: $0.rankChange, currentRank: $0.currentRank, previousRank: $0.previousRank,
                        artwork: artworkLookup.artists[UInt64($0.id) ?? 0] ?? artworkLookup.artistsByName[$0.title.normalizedArtworkKey]
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
                        artwork: artworkLookup.songs[$0.id],
                        recordingIdentity: $0.recordingIdentity,
                        playbackStoreID: $0.playbackStoreID
                    )
                },
                unattributedPlayDelta: unattributedPlayDelta ?? 0,
                unattributedListeningDuration: unattributedListeningDuration ?? 0
            )
        }

        func compacted() -> SyncedMonthlyRecap {
            SyncedMonthlyRecap(
                recap: monthlyRecap(artworkLookup: ArtworkLookup(sourceSongs: [])),
                reliabilityPolicyVersion: reliabilityPolicyVersion
            )
        }
    }

    fileprivate struct SyncedYearlyRecap: Codable, Equatable, Identifiable {
        let year: Int
        let recap: SyncedMonthlyRecap

        var id: Int { year }

        init(
            year: Int,
            recap: MonthlyRecap,
            reliabilityPolicyVersion: Int? = MonthlyRecapSnapshotStore.currentCounterReliabilityPolicyVersion
        ) {
            self.year = year
            self.recap = SyncedMonthlyRecap(
                recap: recap,
                reliabilityPolicyVersion: reliabilityPolicyVersion
            )
        }

        init(year: Int, recap: SyncedMonthlyRecap) {
            self.year = year
            self.recap = recap
        }

        func monthlyRecap(artworkLookup: ArtworkLookup) -> MonthlyRecap {
            recap.monthlyRecap(artworkLookup: artworkLookup)
        }
    }

    fileprivate struct UnattributedRecapInterval: Codable, Equatable, Identifiable {
        let id: String
        let startedAt: Date
        let endedAt: Date
        let deviceIdentifier: String
        let recap: SyncedMonthlyRecap

        init(startedAt: Date, endedAt: Date, deviceIdentifier: String, recap: MonthlyRecap) {
            let startMilliseconds = Int64((startedAt.timeIntervalSince1970 * 1_000).rounded())
            let endMilliseconds = Int64((endedAt.timeIntervalSince1970 * 1_000).rounded())
            id = "\(deviceIdentifier)|\(startMilliseconds)|\(endMilliseconds)"
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.deviceIdentifier = deviceIdentifier
            self.recap = SyncedMonthlyRecap(recap: recap, preservingAllRankings: true)
        }

        private init(
            id: String,
            startedAt: Date,
            endedAt: Date,
            deviceIdentifier: String,
            recap: SyncedMonthlyRecap
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.deviceIdentifier = deviceIdentifier
            self.recap = recap
        }

        func compacted() -> UnattributedRecapInterval {
            UnattributedRecapInterval(
                id: id,
                startedAt: startedAt,
                endedAt: endedAt,
                deviceIdentifier: deviceIdentifier,
                recap: recap.compacted()
            )
        }

        func monthlyRecap(artworkLookup: ArtworkLookup) -> MonthlyRecap {
            recap.monthlyRecap(artworkLookup: artworkLookup)
        }
    }

    private struct SyncedRecapSummaries: Codable, Equatable {
        let monthlyRecaps: [SyncedMonthlyRecap]
        let yearlyRecaps: [SyncedYearlyRecap]
    }

    private struct ReliabilityEvent: Codable, Equatable, Identifiable {
        enum Kind: String, Codable {
            case rejectedCounterRegression
            case rejectedCoverageDrop
        }

        let id: String
        let occurredAt: Date
        let kind: Kind
        let coverageSignature: String?
        let scannedSongCount: Int
        let comparableItemCount: Int
        let regressedItemCount: Int
        let previousComparablePlayCount: Int
        let regressedPlayCount: Int
    }

    private struct StoredSnapshots: Codable {
        var schemaVersion: Int
        var gapPolicyVersion: Int
        var counterReliabilityPolicyVersion: Int
        var snapshots: [LibrarySnapshot]
        var monthlyLedgers: [SyncedMonthlyRecap]
        var syncedRecaps: [SyncedMonthlyRecap]
        var syncedYearlyRecaps: [SyncedYearlyRecap]
        var unattributedIntervals: [UnattributedRecapInterval]
        var lastTrustedObservationAt: Date?
        var reliabilityEvents: [ReliabilityEvent]

        init(
            schemaVersion: Int,
            gapPolicyVersion: Int = 1,
            counterReliabilityPolicyVersion: Int = 1,
            snapshots: [LibrarySnapshot],
            monthlyLedgers: [SyncedMonthlyRecap] = [],
            syncedRecaps: [SyncedMonthlyRecap] = [],
            syncedYearlyRecaps: [SyncedYearlyRecap] = [],
            unattributedIntervals: [UnattributedRecapInterval] = [],
            lastTrustedObservationAt: Date? = nil,
            reliabilityEvents: [ReliabilityEvent] = []
        ) {
            self.schemaVersion = schemaVersion
            self.gapPolicyVersion = gapPolicyVersion
            self.counterReliabilityPolicyVersion = counterReliabilityPolicyVersion
            self.snapshots = snapshots
            self.monthlyLedgers = monthlyLedgers
            self.syncedRecaps = syncedRecaps
            self.syncedYearlyRecaps = syncedYearlyRecaps
            self.unattributedIntervals = unattributedIntervals
            self.lastTrustedObservationAt = lastTrustedObservationAt
            self.reliabilityEvents = reliabilityEvents
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case gapPolicyVersion
            case counterReliabilityPolicyVersion
            case snapshots
            case monthlyLedgers
            case syncedRecaps
            case syncedYearlyRecaps
            case unattributedIntervals
            case lastTrustedObservationAt
            case reliabilityEvents
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            gapPolicyVersion = try container.decodeIfPresent(Int.self, forKey: .gapPolicyVersion) ?? 0
            counterReliabilityPolicyVersion = try container.decodeIfPresent(
                Int.self,
                forKey: .counterReliabilityPolicyVersion
            ) ?? 0
            snapshots = try container.decode([LibrarySnapshot].self, forKey: .snapshots)
            monthlyLedgers = try container.decodeIfPresent([SyncedMonthlyRecap].self, forKey: .monthlyLedgers) ?? []
            syncedRecaps = try container.decodeIfPresent([SyncedMonthlyRecap].self, forKey: .syncedRecaps) ?? []
            syncedYearlyRecaps = try container.decodeIfPresent([SyncedYearlyRecap].self, forKey: .syncedYearlyRecaps) ?? []
            unattributedIntervals = try container.decodeIfPresent(
                [UnattributedRecapInterval].self,
                forKey: .unattributedIntervals
            ) ?? []
            lastTrustedObservationAt = try container.decodeIfPresent(Date.self, forKey: .lastTrustedObservationAt)
            reliabilityEvents = try container.decodeIfPresent(
                [ReliabilityEvent].self,
                forKey: .reliabilityEvents
            ) ?? []
        }
    }

    /// A compact, delta-encoded persistence layer. Each row stores only songs that
    /// changed since the preceding observation for that device, while finalized recap
    /// summaries remain independently readable from the small summary cache.
    private final class LedgerDatabase {
        private static let schemaVersion = 3
        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        private struct SnapshotHeader: Codable {
            let capturedAt: Date
            let reason: RecapSnapshotReason?
            let appVersion: String?
            let scannedSongCount: Int?
            let deviceIdentifier: String?
            let aggregateCounters: AggregateCounters?
            let songOrder: [UInt64]?
            let changes: [SongChange]
        }

        private struct SongChange: Codable {
            let id: UInt64
            let song: SongSnapshot?
        }

        private enum LedgerError: Error {
            case open(Int32, String)
            case sqlite(Int32, String)
            case corrupt(String)
        }

        let url: URL

        init(url: URL) {
            self.url = url
        }

        static func isDefinitiveCorruption(_ error: Error) -> Bool {
            if case LedgerError.corrupt = error {
                return true
            }
            if case LedgerError.sqlite(let code, _) = error {
                return code == SQLITE_CORRUPT || code == SQLITE_NOTADB
            }
            if error is DecodingError {
                return true
            }
            return (error as? CocoaError)?.code == .fileReadCorruptFile
        }

        var exists: Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        func load() throws -> StoredSnapshots? {
            guard exists else { return nil }
            let database = try open()
            defer { sqlite3_close(database) }
            try configure(database)

            guard try metadataInteger("schemaVersion", in: database) == Self.schemaVersion else {
                throw LedgerError.corrupt("Unsupported recap ledger schema")
            }

            let syncedRecaps: [SyncedMonthlyRecap] = try metadataCodable("monthlyRecaps", in: database) ?? []
            let gapPolicyVersion = try metadataInteger("gapPolicyVersion", in: database) ?? 0
            let counterReliabilityPolicyVersion = try metadataInteger(
                "counterReliabilityPolicyVersion",
                in: database
            ) ?? 0
            let monthlyLedgers: [SyncedMonthlyRecap] = try metadataCodable("monthlyLedgers", in: database) ?? syncedRecaps
            let syncedYearlyRecaps: [SyncedYearlyRecap] = try metadataCodable("yearlyRecaps", in: database) ?? []
            let unattributedIntervals: [UnattributedRecapInterval] = try metadataCodable(
                "unattributedIntervals",
                in: database
            ) ?? []
            let trustedObservationDates: [Date] = try metadataCodable(
                "lastTrustedObservationAt",
                in: database
            ) ?? []
            let lastTrustedObservationAt = trustedObservationDates.first
            let reliabilityEvents: [ReliabilityEvent] = try metadataCodable(
                "reliabilityEvents",
                in: database
            ) ?? []
            let sql = "SELECT record FROM snapshots ORDER BY sequence ASC"
            let statement = try prepare(sql, in: database)
            defer { sqlite3_finalize(statement) }

            var statesByDevice: [String: [UInt64: SongSnapshot]] = [:]
            var snapshots: [LibrarySnapshot] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let record = try data(at: 0, from: statement)
                let header = try JSONDecoder.playCount.decode(SnapshotHeader.self, from: record)
                let deviceKey = header.deviceIdentifier ?? "legacy"
                var state = statesByDevice[deviceKey] ?? [:]
                for change in header.changes {
                    if let song = change.song {
                        state[change.id] = song
                    } else {
                        state.removeValue(forKey: change.id)
                    }
                }
                statesByDevice[deviceKey] = state
                let orderedSongs: [SongSnapshot]
                if let songOrder = header.songOrder {
                    let orderedIDs = Set(songOrder)
                    orderedSongs = songOrder.compactMap { state[$0] } + state.values
                        .filter { !orderedIDs.contains($0.id) }
                        .sorted { $0.id < $1.id }
                } else {
                    orderedSongs = state.values.sorted { $0.id < $1.id }
                }
                snapshots.append(
                    LibrarySnapshot(
                        capturedAt: header.capturedAt,
                        reason: header.reason,
                        appVersion: header.appVersion,
                        scannedSongCount: header.scannedSongCount,
                        deviceIdentifier: header.deviceIdentifier,
                        aggregateCounters: header.aggregateCounters,
                        songs: orderedSongs
                    )
                )
            }
            guard sqlite3_errcode(database) == SQLITE_OK || sqlite3_errcode(database) == SQLITE_DONE else {
                throw error(for: database)
            }

            return StoredSnapshots(
                schemaVersion: Self.schemaVersion,
                gapPolicyVersion: gapPolicyVersion,
                counterReliabilityPolicyVersion: counterReliabilityPolicyVersion,
                snapshots: snapshots,
                monthlyLedgers: monthlyLedgers,
                syncedRecaps: syncedRecaps,
                syncedYearlyRecaps: syncedYearlyRecaps,
                unattributedIntervals: unattributedIntervals,
                lastTrustedObservationAt: lastTrustedObservationAt,
                reliabilityEvents: reliabilityEvents
            )
        }

        func save(_ stored: StoredSnapshots) throws {
            let database = try open()
            defer { sqlite3_close(database) }
            try configure(database)
            try execute("BEGIN IMMEDIATE TRANSACTION", in: database)

            do {
                let existingIDs = try snapshotIdentifiers(in: database)
                let intendedIDs = stored.snapshots.map(\.syncIdentifier)
                let canAppend = existingIDs.count <= intendedIDs.count &&
                    Array(intendedIDs.prefix(existingIDs.count)) == existingIDs

                let startIndex: Int
                if canAppend {
                    startIndex = existingIDs.count
                } else {
                    try execute("DELETE FROM snapshots", in: database)
                    startIndex = 0
                }

                if startIndex < stored.snapshots.count {
                    for index in startIndex..<stored.snapshots.count {
                        let snapshot = stored.snapshots[index]
                        let previous = stored.snapshots[..<index].last {
                            ($0.deviceIdentifier ?? "legacy") == (snapshot.deviceIdentifier ?? "legacy")
                        }
                        try insert(
                            snapshot,
                            previous: previous,
                            sequence: index,
                            into: database
                        )
                    }
                }

                try setMetadataInteger(Self.schemaVersion, for: "schemaVersion", in: database)
                try setMetadataInteger(stored.gapPolicyVersion, for: "gapPolicyVersion", in: database)
                try setMetadataInteger(
                    stored.counterReliabilityPolicyVersion,
                    for: "counterReliabilityPolicyVersion",
                    in: database
                )
                try setMetadataCodable(stored.monthlyLedgers, for: "monthlyLedgers", in: database)
                try setMetadataCodable(stored.syncedRecaps, for: "monthlyRecaps", in: database)
                try setMetadataCodable(stored.syncedYearlyRecaps, for: "yearlyRecaps", in: database)
                try setMetadataCodable(stored.unattributedIntervals, for: "unattributedIntervals", in: database)
                try setMetadataCodable(
                    stored.lastTrustedObservationAt.map { [$0] } ?? [],
                    for: "lastTrustedObservationAt",
                    in: database
                )
                try setMetadataCodable(stored.reliabilityEvents, for: "reliabilityEvents", in: database)
                try execute("COMMIT", in: database)
            } catch {
                try? execute("ROLLBACK", in: database)
                throw error
            }
        }

        private func insert(
            _ snapshot: LibrarySnapshot,
            previous: LibrarySnapshot?,
            sequence: Int,
            into database: OpaquePointer
        ) throws {
            let previousSongs = Dictionary(uniqueKeysWithValues: (previous?.songs ?? []).map { ($0.id, $0) })
            let currentSongs = Dictionary(uniqueKeysWithValues: snapshot.songs.map { ($0.id, $0) })
            var changes = currentSongs.compactMap { id, song -> SongChange? in
                previousSongs[id] == song ? nil : SongChange(id: id, song: song)
            }
            changes.append(contentsOf: previousSongs.keys.compactMap { id in
                currentSongs[id] == nil ? SongChange(id: id, song: nil) : nil
            })
            changes.sort { $0.id < $1.id }

            let header = SnapshotHeader(
                capturedAt: snapshot.capturedAt,
                reason: snapshot.reason,
                appVersion: snapshot.appVersion,
                scannedSongCount: snapshot.scannedSongCount,
                deviceIdentifier: snapshot.deviceIdentifier,
                aggregateCounters: snapshot.aggregateCounters,
                songOrder: snapshot.songs.map(\.id),
                changes: changes
            )
            let encoded = try JSONEncoder.playCount.encode(header)
            let statement = try prepare(
                "INSERT INTO snapshots(sequence, identifier, record) VALUES (?, ?, ?)",
                in: database
            )
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, sqlite3_int64(sequence))
            try bind(snapshot.syncIdentifier, at: 2, to: statement)
            try bind(encoded, at: 3, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw error(for: database) }
        }

        private func open() throws -> OpaquePointer {
            var database: OpaquePointer?
            let result = sqlite3_open_v2(
                url.path,
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
            guard result == SQLITE_OK, let database else {
                let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
                if let database { sqlite3_close(database) }
                throw LedgerError.open(result, message)
            }
            sqlite3_busy_timeout(database, 5_000)
            return database
        }

        private func configure(_ database: OpaquePointer) throws {
            try execute("PRAGMA journal_mode=WAL", in: database)
            try execute("PRAGMA synchronous=NORMAL", in: database)
            try execute("PRAGMA foreign_keys=ON", in: database)
            try execute(
                "CREATE TABLE IF NOT EXISTS snapshots (sequence INTEGER PRIMARY KEY, identifier TEXT NOT NULL UNIQUE, record BLOB NOT NULL)",
                in: database
            )
            try execute(
                "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value BLOB NOT NULL)",
                in: database
            )
        }

        private func snapshotIdentifiers(in database: OpaquePointer) throws -> [String] {
            let statement = try prepare("SELECT identifier FROM snapshots ORDER BY sequence ASC", in: database)
            defer { sqlite3_finalize(statement) }
            var identifiers: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let text = sqlite3_column_text(statement, 0) else {
                    throw LedgerError.corrupt("Snapshot identifier is missing")
                }
                identifiers.append(String(cString: text))
            }
            return identifiers
        }

        private func metadataInteger(_ key: String, in database: OpaquePointer) throws -> Int? {
            guard let data = try metadataData(key, in: database),
                  let string = String(data: data, encoding: .utf8) else { return nil }
            return Int(string)
        }

        private func metadataCodable<Value: Decodable>(
            _ key: String,
            in database: OpaquePointer
        ) throws -> Value? {
            guard let data = try metadataData(key, in: database) else { return nil }
            return try JSONDecoder.playCount.decode(Value.self, from: data)
        }

        private func metadataData(_ key: String, in database: OpaquePointer) throws -> Data? {
            let statement = try prepare("SELECT value FROM metadata WHERE key = ?", in: database)
            defer { sqlite3_finalize(statement) }
            try bind(key, at: 1, to: statement)
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                return try data(at: 0, from: statement)
            case SQLITE_DONE:
                return nil
            default:
                throw error(for: database)
            }
        }

        private func setMetadataInteger(_ value: Int, for key: String, in database: OpaquePointer) throws {
            try setMetadataData(Data(String(value).utf8), for: key, in: database)
        }

        private func setMetadataCodable<Value: Encodable>(
            _ value: Value,
            for key: String,
            in database: OpaquePointer
        ) throws {
            try setMetadataData(try JSONEncoder.playCount.encode(value), for: key, in: database)
        }

        private func setMetadataData(_ value: Data, for key: String, in database: OpaquePointer) throws {
            let statement = try prepare(
                "INSERT INTO metadata(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                in: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(key, at: 1, to: statement)
            try bind(value, at: 2, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw error(for: database) }
        }

        private func execute(_ sql: String, in database: OpaquePointer) throws {
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw error(for: database)
            }
        }

        private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw error(for: database)
            }
            return statement
        }

        private func bind(_ value: String, at index: Int32, to statement: OpaquePointer) throws {
            let result = sqlite3_bind_text(statement, index, value, -1, Self.transient)
            guard result == SQLITE_OK else {
                throw LedgerError.sqlite(result, "Could not bind text")
            }
        }

        private func bind(_ value: Data, at index: Int32, to statement: OpaquePointer) throws {
            let result = value.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
            }
            guard result == SQLITE_OK else { throw LedgerError.sqlite(result, "Could not bind data") }
        }

        private func data(at index: Int32, from statement: OpaquePointer) throws -> Data {
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0 else { return Data() }
            guard let bytes = sqlite3_column_blob(statement, index) else {
                throw LedgerError.corrupt("Stored recap data is missing")
            }
            return Data(bytes: bytes, count: count)
        }

        private func error(for database: OpaquePointer) -> LedgerError {
            LedgerError.sqlite(sqlite3_errcode(database), String(cString: sqlite3_errmsg(database)))
        }
    }

    private enum LegacyStreamError: Error {
        case snapshotsArrayMissing
        case malformedSnapshotArray
        case truncatedSnapshot
    }

    private struct SongDelta {
        let latest: SongSnapshot
        let playDelta: Int
        let skipDelta: Int
        let recordingIdentity: String
        let playbackStoreID: String?
        let isNewSong: Bool

        var listeningDuration: TimeInterval {
            TimeInterval(playDelta) * latest.playbackDuration
        }
    }

    private struct CounterEpochAnalysis {
        let deltas: [SongDelta]
        let removedPlayCount: Int
        let removedSkipCount: Int
        let removedListeningDuration: TimeInterval
    }

    private struct CounterEpoch {
        let recordingIdentity: String
        let playbackStoreID: String?
        let baselinePlayCount: Int
        let baselineSkipCount: Int
        var maximumPlayCount: Int
        var maximumSkipCount: Int
        var latest: SongSnapshot
    }

    private struct RecordingIdentityResolver {
        private let uniqueStoreIDByFingerprint: [String: String]
        private let ambiguousFingerprints: Set<String>

        init(snapshots: [LibrarySnapshot]) {
            var storeIDsByFingerprint: [String: Set<String>] = [:]
            var ambiguousFingerprints: Set<String> = []

            for snapshot in snapshots {
                let IDsByFingerprint = Dictionary(grouping: snapshot.songs, by: \.recordingFingerprint)
                for (fingerprint, songs) in IDsByFingerprint {
                    if Set(songs.map(\.id)).count > 1 {
                        ambiguousFingerprints.insert(fingerprint)
                    }
                    for song in songs {
                        guard let playbackStoreID = song.playbackStoreID else { continue }
                        storeIDsByFingerprint[fingerprint, default: []].insert(playbackStoreID)
                    }
                }
            }

            uniqueStoreIDByFingerprint = storeIDsByFingerprint.compactMapValues { storeIDs in
                storeIDs.count == 1 ? storeIDs.first : nil
            }
            self.ambiguousFingerprints = ambiguousFingerprints
        }

        func identity(for song: SongSnapshot) -> String {
            let fingerprint = song.recordingFingerprint
            if ambiguousFingerprints.contains(fingerprint) {
                return "duplicate:\(fingerprint):\(song.id)"
            }
            if let playbackStoreID = song.playbackStoreID
                ?? uniqueStoreIDByFingerprint[fingerprint] {
                return "store:\(playbackStoreID)"
            }
            return "metadata:\(fingerprint)"
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

                    let albumKey = Self.albumKey(title: song.albumTitle, artist: song.albumArtist)
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
            return albumsByName[Self.albumKey(title: song.albumTitle, artist: song.albumArtist)]
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
    private let ledgerURL: URL
    private let summaryFileURL: URL
    private let summaryBackupFileURL: URL
    private let ledgerAuthorityMarkerURL: URL
    private let calendar: Calendar
    private let deviceIdentifier: String
    private let legacyDeviceIdentifierToBridge: String?
    private let persistenceReadAllowed: () -> Bool
    private let persistenceWriteAllowed: () -> Bool
    private let legacyArchiveReadAllowed: () -> Bool
    private let legacyArchiveRetirementAllowed: () -> Bool
    private let accessQueue = DispatchQueue(label: "com.playcount.monthly-recap-snapshots")
    private let retentionMonths = 18
    private let minimumSnapshotInterval: TimeInterval = 60 * 30
    private let minimumComparableCoverageRatio = 0.9
    private let maximumListeningElapsedRatio = 1.25
    private var loadedSnapshots: StoredSnapshots?
    private var ledgerReadUnavailable = false
    private var ledgerLoadRetryPending = false
    private var legacyArchiveReadRetryPending = false
    private var persistenceSavePending = false
    private var mergeSavePending = false
    private var quarantinedLedgerURLsPendingCleanup: [URL] = []

    private static let legacyDeviceBridgeDefaultsKey = "PlayCountRecapSnapshotLegacyDeviceIdentifierToBridge"

    static func resolvedDeviceIdentifier(
        keychainIdentifier: String?,
        defaultsIdentifier: String?,
        storedVendorIdentifier: String?,
        currentVendorIdentifier: String?
    ) -> String {
        if let keychainIdentifier, !keychainIdentifier.isEmpty {
            return keychainIdentifier
        }
        if let defaultsIdentifier,
           !defaultsIdentifier.isEmpty,
           let storedVendorIdentifier,
           let currentVendorIdentifier,
           storedVendorIdentifier == currentVendorIdentifier {
            return defaultsIdentifier
        }
        return UUID().uuidString
    }

    static func resolvedLegacyBridgeIdentifier(
        existingBridgeIdentifier: String?,
        keychainIdentifier: String?,
        defaultsIdentifier: String?,
        storedVendorIdentifier: String?,
        currentVendorIdentifier: String?,
        resolvedDeviceIdentifier: String
    ) -> String? {
        if let storedVendorIdentifier,
           let currentVendorIdentifier,
           storedVendorIdentifier != currentVendorIdentifier {
            return nil
        }
        if keychainIdentifier == nil,
           storedVendorIdentifier == nil,
           let defaultsIdentifier,
           !defaultsIdentifier.isEmpty,
           defaultsIdentifier != resolvedDeviceIdentifier {
            return defaultsIdentifier
        }
        return existingBridgeIdentifier
    }

    private static let persistedLocalDeviceIdentifier: String = {
        let key = "PlayCountRecapSnapshotDeviceIdentifier"
        let vendorKey = "PlayCountRecapSnapshotDeviceVendorIdentifier"
        let service = "com.nadavavital.PlayCount.recap-device"
        let account = "local-device-identifier"
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var lookup = baseQuery
        lookup.merge([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new }
        var result: CFTypeRef?
        let keychainIdentifier: String?
        if SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let existing = String(data: data, encoding: .utf8),
           !existing.isEmpty {
            keychainIdentifier = existing
        } else {
            keychainIdentifier = nil
        }

        let currentVendorIdentifier = UIDevice.current.identifierForVendor?.uuidString
        let defaultsIdentifier = UserDefaults.standard.string(forKey: key)
        let storedVendorIdentifier = UserDefaults.standard.string(forKey: vendorKey)
        let identifier = resolvedDeviceIdentifier(
            keychainIdentifier: keychainIdentifier,
            defaultsIdentifier: defaultsIdentifier,
            storedVendorIdentifier: storedVendorIdentifier,
            currentVendorIdentifier: currentVendorIdentifier
        )
        let bridgeIdentifier = resolvedLegacyBridgeIdentifier(
            existingBridgeIdentifier: UserDefaults.standard.string(forKey: legacyDeviceBridgeDefaultsKey),
            keychainIdentifier: keychainIdentifier,
            defaultsIdentifier: defaultsIdentifier,
            storedVendorIdentifier: storedVendorIdentifier,
            currentVendorIdentifier: currentVendorIdentifier,
            resolvedDeviceIdentifier: identifier
        )
        if let bridgeIdentifier {
            // This state is ambiguous: it can be an in-place upgrade or a backup
            // restored to new hardware. Rotate to a hardware-safe stream, then
            // bridge exactly the first new snapshot from the legacy stream.
            UserDefaults.standard.set(bridgeIdentifier, forKey: legacyDeviceBridgeDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: legacyDeviceBridgeDefaultsKey)
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(identifier.utf8)
        ]
        if keychainIdentifier == nil {
            SecItemDelete(baseQuery as CFDictionary)
            SecItemAdd(attributes as CFDictionary, nil)
        }
        UserDefaults.standard.set(identifier, forKey: key)
        UserDefaults.standard.set(currentVendorIdentifier, forKey: vendorKey)
        return identifier
    }()

    private static func localDeviceIdentifier() -> String {
        persistedLocalDeviceIdentifier
    }

    private static func localLegacyDeviceIdentifierToBridge() -> String? {
        UserDefaults.standard.string(forKey: legacyDeviceBridgeDefaultsKey)
    }

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        calendar: Calendar = .current,
        deviceIdentifier: String = MonthlyRecapSnapshotStore.localDeviceIdentifier(),
        legacyDeviceIdentifierToBridge: String? = MonthlyRecapSnapshotStore.localLegacyDeviceIdentifierToBridge(),
        persistenceReadAllowed: @escaping () -> Bool = { true },
        persistenceWriteAllowed: @escaping () -> Bool = { true },
        legacyArchiveReadAllowed: @escaping () -> Bool = { true },
        legacyArchiveRetirementAllowed: @escaping () -> Bool = { true }
    ) {
        self.calendar = calendar
        self.deviceIdentifier = deviceIdentifier
        self.legacyDeviceIdentifierToBridge = legacyDeviceIdentifierToBridge
        self.persistenceReadAllowed = persistenceReadAllowed
        self.persistenceWriteAllowed = persistenceWriteAllowed
        self.legacyArchiveReadAllowed = legacyArchiveReadAllowed
        self.legacyArchiveRetirementAllowed = legacyArchiveRetirementAllowed

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
        ledgerURL = resolvedDirectoryURL.appendingPathComponent("recap-ledger.sqlite")
        summaryFileURL = resolvedDirectoryURL.appendingPathComponent("recap-summaries.json")
        summaryBackupFileURL = resolvedDirectoryURL.appendingPathComponent("recap-summaries.previous.json")
        ledgerAuthorityMarkerURL = resolvedDirectoryURL.appendingPathComponent("recap-ledger.authoritative")
    }

    var isPersistenceHealthyForSync: Bool {
        accessQueue.sync {
            _ = loadLocked()
            return !ledgerReadUnavailable && !ledgerLoadRetryPending && !legacyArchiveReadRetryPending &&
                !persistenceSavePending && !mergeSavePending
        }
    }

    func cachedRecapSummaries(
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = []
    ) -> [MonthlyRecap] {
        cachedRecapPresentation(
            sourceSongs: sourceSongs,
            sourceAlbums: sourceAlbums,
            sourceArtists: sourceArtists
        ).monthlyRecaps
    }

    /// Starts any one-time legacy conversion independently of the media-library
    /// query. Call from a utility queue so cached UI remains immediately usable.
    func prepareStorage() {
        accessQueue.sync {
            _ = loadLocked()
        }
    }

    func cachedRecapPresentation(
        sourceSongs: [TopSong] = [],
        sourceAlbums: [TopAlbum] = [],
        sourceArtists: [TopArtist] = [],
        through date: Date = Date()
    ) -> CachedRecapPresentation {
        accessQueue.sync {
            guard let summaries = resolvedSummaryCache() else {
                return .empty
            }
            let artworkLookup = ArtworkLookup(
                sourceSongs: sourceSongs,
                sourceAlbums: sourceAlbums,
                sourceArtists: sourceArtists
            )
            let monthlyRecaps = summaries.monthlyRecaps
                .map { $0.monthlyRecap(artworkLookup: artworkLookup) }
                .sorted { $0.monthStart < $1.monthStart }
            let yearlyRecaps = Dictionary(
                summaries.yearlyRecaps.map { yearly in
                    (yearly.year, yearly.monthlyRecap(artworkLookup: artworkLookup))
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let availableMonthStarts = Array(Set(monthlyRecaps.map {
                calendar.startOfMonth(containing: $0.monthStart)
            })).sorted()
            return CachedRecapPresentation(
                monthlyRecaps: monthlyRecaps,
                yearlyRecaps: yearlyRecaps,
                availableMonthStarts: availableMonthStarts
            )
        }
    }

    #if DEBUG
    var debugHasLoadedFullSnapshotStore: Bool {
        accessQueue.sync { loadedSnapshots != nil }
    }

    static func debugSetLegacyDeviceIdentifierToBridge(_ identifier: String?) {
        UserDefaults.standard.set(identifier, forKey: legacyDeviceBridgeDefaultsKey)
    }

    static var debugLegacyDeviceIdentifierToBridge: String? {
        UserDefaults.standard.string(forKey: legacyDeviceBridgeDefaultsKey)
    }

    func debugYearlyReliabilityPolicyVersion(for year: Int) -> Int? {
        accessQueue.sync {
            loadLocked().syncedYearlyRecaps.first { $0.year == year }?.recap.reliabilityPolicyVersion
        }
    }

    func debugCreateLegacyArchiveForMigration() throws {
        try accessQueue.sync {
            let stored = loadLocked()
            let data = try JSONEncoder.playCount.encode(stored)
            try data.write(to: fileURL, options: [.atomic])
            for url in [ledgerURL, URL(fileURLWithPath: ledgerURL.path + "-wal"), URL(fileURLWithPath: ledgerURL.path + "-shm")] {
                try? FileManager.default.removeItem(at: url)
            }
            // This helper intentionally recreates a pre-SQLite installation.
            try? FileManager.default.removeItem(at: ledgerAuthorityMarkerURL)
            loadedSnapshots = nil
        }
    }

    func debugInstallPreGapPolicyRecap(_ recap: MonthlyRecap) {
        accessQueue.sync {
            var stored = loadLocked()
            let ledger = SyncedMonthlyRecap(
                recap: recap,
                preservingAllRankings: true,
                reliabilityPolicyVersion: nil
            )
            stored.gapPolicyVersion = 0
            stored.unattributedIntervals = []
            stored.monthlyLedgers.removeAll { $0.monthStart == recap.monthStart }
            stored.monthlyLedgers.append(ledger)
            stored.syncedRecaps.removeAll { $0.monthStart == recap.monthStart }
            stored.syncedRecaps.append(ledger.compacted())
            stored.syncedYearlyRecaps = yearlyRecaps(
                from: stored.monthlyLedgers,
                unattributedIntervals: []
            )
            saveLocked(stored)
            loadedSnapshots = nil
        }
    }

    func debugInstallPreCounterReliabilityPolicyRecap(_ recap: MonthlyRecap) {
        accessQueue.sync {
            var stored = loadLocked()
            let ledger = SyncedMonthlyRecap(
                recap: recap,
                preservingAllRankings: true,
                reliabilityPolicyVersion: nil
            )
            stored.counterReliabilityPolicyVersion = 0
            stored.monthlyLedgers.removeAll { $0.monthStart == recap.monthStart }
            stored.monthlyLedgers.append(ledger)
            stored.syncedRecaps.removeAll { $0.monthStart == recap.monthStart }
            stored.syncedRecaps.append(ledger.compacted())
            stored.syncedYearlyRecaps = yearlyRecaps(
                from: stored.monthlyLedgers,
                unattributedIntervals: stored.unattributedIntervals
            )
            saveLocked(stored)
            loadedSnapshots = nil
        }
    }

    func debugInstallPreCounterReliabilityPolicyEvidence(
        monthlyLedgerRecaps: [MonthlyRecap],
        summaryOnlyRecaps: [MonthlyRecap]
    ) {
        accessQueue.sync {
            var stored = loadLocked()
            stored.counterReliabilityPolicyVersion = Self.currentCounterReliabilityPolicyVersion - 1
            stored.monthlyLedgers = monthlyLedgerRecaps.map {
                SyncedMonthlyRecap(
                    recap: $0,
                    preservingAllRankings: true,
                    reliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion - 1
                )
            }
            stored.syncedRecaps = (monthlyLedgerRecaps + summaryOnlyRecaps).map {
                SyncedMonthlyRecap(
                    recap: $0,
                    preservingAllRankings: false,
                    reliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion - 1
                )
            }
            stored.syncedYearlyRecaps = []
            saveLocked(stored)
            loadedSnapshots = nil
        }
    }

    func debugInstallPreCounterReliabilityPolicyRecapMissingListenedArtistCount(_ recap: MonthlyRecap) throws {
        try accessQueue.sync {
            var stored = loadLocked()
            let modernLedger = SyncedMonthlyRecap(
                recap: recap,
                preservingAllRankings: true,
                reliabilityPolicyVersion: nil
            )
            let ledger = try Self.removingListenedArtistCount(from: modernLedger)
            stored.counterReliabilityPolicyVersion = 0
            stored.monthlyLedgers.removeAll { $0.monthStart == recap.monthStart }
            stored.monthlyLedgers.append(ledger)
            stored.syncedRecaps.removeAll { $0.monthStart == recap.monthStart }
            stored.syncedRecaps.append(try Self.removingListenedArtistCount(from: ledger.compacted()))
            stored.syncedYearlyRecaps = try yearlyRecaps(
                from: stored.monthlyLedgers,
                unattributedIntervals: stored.unattributedIntervals
            ).map {
                SyncedYearlyRecap(
                    year: $0.year,
                    recap: try Self.removingListenedArtistCount(from: $0.recap)
                )
            }
            saveLocked(stored)
            loadedSnapshots = nil
        }
    }

    private static func removingListenedArtistCount(from recap: SyncedMonthlyRecap) throws -> SyncedMonthlyRecap {
        let encoded = try JSONEncoder.playCount.encode(recap)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        object.removeValue(forKey: "listenedArtistCount")
        return try JSONDecoder.playCount.decode(
            SyncedMonthlyRecap.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
    }

    func debugRemoveYearlyRecaps() {
        accessQueue.sync {
            var stored = loadLocked()
            stored.syncedYearlyRecaps = []
            saveLocked(stored)
            loadedSnapshots = nil
        }
    }

    func debugInstallSyncedRecapCandidates(
        _ candidates: [(recap: MonthlyRecap, reliabilityPolicyVersion: Int?)]
    ) {
        accessQueue.sync {
            var stored = loadLocked()
            let monthStarts = Set(candidates.map { $0.recap.monthStart })
            stored.monthlyLedgers.removeAll { monthStarts.contains($0.monthStart) }
            stored.syncedRecaps.removeAll { monthStarts.contains($0.monthStart) }
            for candidate in candidates {
                let ledger = SyncedMonthlyRecap(
                    recap: candidate.recap,
                    preservingAllRankings: true,
                    reliabilityPolicyVersion: candidate.reliabilityPolicyVersion
                )
                stored.monthlyLedgers.append(ledger)
                stored.syncedRecaps.append(ledger.compacted())
            }
            stored.monthlyLedgers = Self.mergedSyncedRecaps(stored.monthlyLedgers)
            stored.syncedRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps)
            saveLocked(stored)
        }
    }

    func debugInstallPreMonthIdentityPolicyRecaps(_ recaps: [MonthlyRecap]) {
        accessQueue.sync {
            var stored = loadLocked()
            stored.counterReliabilityPolicyVersion = 1
            stored.monthlyLedgers = recaps.map {
                SyncedMonthlyRecap(
                    recap: $0,
                    preservingAllRankings: true,
                    reliabilityPolicyVersion: 1
                )
            }
            stored.syncedRecaps = stored.monthlyLedgers.map { $0.compacted() }
            stored.syncedYearlyRecaps = yearlyRecaps(
                from: stored.monthlyLedgers,
                unattributedIntervals: stored.unattributedIntervals
            )
            saveLocked(stored)
            loadedSnapshots = nil
        }
    }
    #endif

    func record(
        songs: [TopSong],
        albums: [TopAlbum] = [],
        artists: [TopArtist] = [],
        at capturedAt: Date,
        reason: RecapSnapshotReason,
        shouldCommit: @Sendable () -> Bool = { true }
    ) -> MonthlyRecap {
        accessQueue.sync {
            recordLocked(
                songs: songs,
                albums: albums,
                artists: artists,
                at: capturedAt,
                reason: reason,
                shouldCommit: shouldCommit
            )
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
            let stored = loadLocked()
            let currentMonth = calendar.startOfMonth(containing: date)
            let persistedMonths = (stored.monthlyLedgers.isEmpty ? stored.syncedRecaps : stored.monthlyLedgers)
                .map { calendar.startOfMonth(containing: $0.monthStart) }
                .filter { $0 <= currentMonth }
            let snapshotMonths = stored.snapshots.map {
                calendar.startOfMonth(containing: $0.capturedAt)
            }.filter { $0 <= currentMonth }
            let trackedMonths = Array(Set(persistedMonths + snapshotMonths)).sorted()
            return trackedMonths.isEmpty ? [currentMonth] : trackedMonths
        }
    }

    func syncPayloads(
        shouldCommit: @Sendable () -> Bool = { true }
    ) -> [RecapSnapshotSyncPayload] {
        accessQueue.sync {
            var stored = loadLocked()
            var didChange = backfillAggregateCounters(in: &stored)
            if compactRetainedCanonicalSnapshots(in: &stored, now: Date()) {
                didChange = true
            }
            let retainedIntervals = durableUnattributedIntervals(stored.unattributedIntervals)
            if retainedIntervals != stored.unattributedIntervals {
                stored.unattributedIntervals = retainedIntervals
                didChange = true
            }
            if didChange && updateSyncedRecaps(in: &stored, snapshots: stored.snapshots) {
                didChange = true
            }
            if didChange {
                guard shouldCommit() else { return [] }
                guard saveLocked(stored) else { return [] }
            }
            let encodedRecaps = Self.encodedSyncedRecaps(stored.syncedRecaps)
            let encodedYearlyRecaps = Self.encodedSyncedYearlyRecaps(stored.syncedYearlyRecaps)
            let encodedUnattributedIntervals = Self.encodedUnattributedIntervals(stored.unattributedIntervals)
            let syncSnapshots = compactSnapshotsForCloudSync(
                from: stored.snapshots,
                currentDeviceIdentifier: deviceIdentifier
            )
            let prioritySongIDs = syncPrioritySongIDsBySnapshotKey(
                for: syncSnapshots,
                currentDeviceIdentifier: deviceIdentifier
            )
            return Self.attachRecapSummariesToLatestPayload(
                syncSnapshots.sortedForSyncPayloads().compactMap { snapshot in
                    snapshot.syncPayload(
                        prioritySongIDs: prioritySongIDs[snapshot.syncPayloadKey] ?? []
                    )
                },
                encodedRecaps: encodedRecaps,
                encodedYearlyRecaps: encodedYearlyRecaps,
                encodedUnattributedIntervals: encodedUnattributedIntervals,
                archiveReliabilityPolicyVersion: Self.archiveReliabilityPolicyVersion(in: stored),
                archiveCapturedAt: Self.archiveCapturedAt(in: stored)
            )
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
            let retainedIntervals = durableUnattributedIntervals(stored.unattributedIntervals)
            if retainedIntervals != stored.unattributedIntervals {
                stored.unattributedIntervals = retainedIntervals
                didChange = true
            }
            if didChange && updateSyncedRecaps(in: &stored, snapshots: stored.snapshots) {
                didChange = true
            }
            if didChange {
                guard saveLocked(stored) else { return [] }
            }
            let localSnapshots = compactSnapshotsForCloudSync(
                from: stored.snapshots.filter {
                    $0.belongsToLocalDevice(currentDeviceIdentifier: deviceIdentifier)
                },
                currentDeviceIdentifier: deviceIdentifier
            )
            let prioritySongIDs = syncPrioritySongIDsBySnapshotKey(
                for: localSnapshots,
                currentDeviceIdentifier: deviceIdentifier
            )
            let encodedRecaps = Self.encodedSyncedRecaps(stored.syncedRecaps)
            let encodedYearlyRecaps = Self.encodedSyncedYearlyRecaps(stored.syncedYearlyRecaps)
            let encodedUnattributedIntervals = Self.encodedUnattributedIntervals(stored.unattributedIntervals)
            return Self.attachRecapSummariesToLatestPayload(
                localSnapshots.sortedForSyncPayloads().compactMap { snapshot in
                    snapshot.syncPayload(
                        prioritySongIDs: prioritySongIDs[snapshot.syncPayloadKey] ?? []
                    )
                },
                encodedRecaps: encodedRecaps,
                encodedYearlyRecaps: encodedYearlyRecaps,
                encodedUnattributedIntervals: encodedUnattributedIntervals,
                archiveReliabilityPolicyVersion: Self.archiveReliabilityPolicyVersion(in: stored),
                archiveCapturedAt: Self.archiveCapturedAt(in: stored)
            )
            .uniquedByID()
        }
    }

    @discardableResult
    func mergeSyncPayloads(
        _ payloads: [RecapSnapshotSyncPayload],
        now: Date = Date(),
        shouldCommit: @Sendable () -> Bool = { true }
    ) -> Bool {
        guard !payloads.isEmpty else { return false }

        return accessQueue.sync {
            guard shouldCommit() else { return false }
            var stored = loadLocked()
            var snapshotsByID: [String: LibrarySnapshot] = [:]
            for snapshot in stored.snapshots {
                snapshotsByID[snapshot.syncIdentifier] = snapshot
            }
            let incomingSyncedRecaps = payloads.flatMap(Self.syncedRecaps)
            let incomingSyncedYearlyRecaps = payloads.flatMap(Self.syncedYearlyRecaps)
            let incomingUnattributedIntervals = payloads.flatMap(Self.unattributedIntervals)
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
            let mergedMonthlyLedgers = Self.mergedSyncedRecaps(stored.monthlyLedgers + incomingSyncedRecaps)
            if mergedMonthlyLedgers != stored.monthlyLedgers {
                stored.monthlyLedgers = mergedMonthlyLedgers
                didChange = true
            }

            let mergedSyncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(stored.syncedYearlyRecaps + incomingSyncedYearlyRecaps)
            if mergedSyncedYearlyRecaps != stored.syncedYearlyRecaps {
                stored.syncedYearlyRecaps = mergedSyncedYearlyRecaps
                didChange = true
            }
            let mergedUnattributedIntervals = Self.mergedUnattributedIntervals(
                stored.unattributedIntervals + incomingUnattributedIntervals
            )
            if mergedUnattributedIntervals != stored.unattributedIntervals {
                stored.unattributedIntervals = durableUnattributedIntervals(mergedUnattributedIntervals)
                didChange = true
            }

            guard didChange else {
                mergeSavePending = false
                return false
            }

            stored.snapshots = retainedCanonicalSnapshots(
                from: Array(snapshotsByID.values).sortedForSyncPayloads(),
                now: now
            )
            let affectedMonths = Set(payloads.flatMap { payload -> [Date] in
                let month = calendar.startOfMonth(containing: payload.capturedAt)
                let next = calendar.date(byAdding: .month, value: 1, to: month)
                return [month] + (next.map { [$0] } ?? [])
            })
            _ = updateSyncedRecaps(
                in: &stored,
                snapshots: stored.snapshots,
                affectedMonthStarts: affectedMonths
            )
            stored.snapshots = compactSnapshotsForLocalStorage(from: stored.snapshots)
            guard shouldCommit() else { return false }
            let didPersist = saveLocked(stored)
            mergeSavePending = !didPersist
            return didPersist
        }
    }

    func debugSummary(at date: Date = Date()) -> String {
        accessQueue.sync {
            let stored = loadLocked()
            let ordered = stored.snapshots.sorted { $0.capturedAt < $1.capturedAt }
            let recap = recap(for: date, snapshots: ordered, syncedRecaps: stored.syncedRecaps)
            let monthInterval = calendar.recapMonthInterval(containing: date)
            let monthStart = monthInterval.start
            let monthEnd = monthInterval.end
            let inMonth = ordered.filter { monthInterval.contains($0.capturedAt) }
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
            Snapshot ledger: \(ledgerURL.path)
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

    func reliabilityStatus() -> RecapReliabilityStatus {
        accessQueue.sync {
            let stored = loadLocked()
            return RecapReliabilityStatus(
                lastTrustedUpdate: stored.lastTrustedObservationAt ?? stored.snapshots.last?.capturedAt,
                lastRejectedObservation: stored.reliabilityEvents.last?.occurredAt,
                recentRejectedObservationCount: stored.reliabilityEvents.count
            )
        }
    }

    func recapDiagnosticsReport(at date: Date = Date()) -> RecapDiagnosticsReport {
        accessQueue.sync {
            makeDiagnosticsReport(from: loadLocked(), at: date)
        }
    }

    func privacySafeDiagnostics(at date: Date = Date()) -> String {
        recapDiagnosticsReport(at: date).exportText
    }

    private func makeDiagnosticsReport(
        from stored: StoredSnapshots,
        at date: Date
    ) -> RecapDiagnosticsReport {
        let rawLedgers = stored.monthlyLedgers.isEmpty ? stored.syncedRecaps : stored.monthlyLedgers
        let canonicalIdentities = rawLedgers.map { Self.canonicalPersistedMonthStart($0.monthStart) }
        let duplicateMonthCount = max(0, rawLedgers.count - Set(canonicalIdentities).count)
        let ledgers = Self.mergedSyncedRecaps(rawLedgers)
        let months = ledgers.reversed().map { ledger in
            let recap = ledger.monthlyRecap(artworkLookup: ArtworkLookup(sourceSongs: []))
            let monthYear = calendar.recapYear(containing: ledger.monthStart)
            let monthNumber = calendar.recapMonth(containing: ledger.monthStart)
            let storedSnapshotCount = stored.snapshots.lazy.filter {
                self.calendar.recapYear(containing: $0.capturedAt) == monthYear &&
                    self.calendar.recapMonth(containing: $0.capturedAt) == monthNumber
            }.count
            return RecapDiagnosticMonth(
                monthStart: ledger.monthStart,
                totalPlayDelta: recap.totalPlayDelta,
                totalListeningDuration: recap.totalListeningDuration,
                recapSnapshotCount: recap.snapshotCount,
                storedSnapshotCount: storedSnapshotCount,
                trackingStart: recap.trackingStart,
                generatedAt: recap.generatedAt,
                unattributedPlayDelta: recap.unattributedPlayDelta,
                reliabilityPolicyVersion: ledger.reliabilityPolicyVersion ?? 0,
                isCanonicalMonthIdentity: ledger.monthStart == Self.canonicalPersistedMonthStart(ledger.monthStart)
            )
        }

        let expectedYearlyRecaps = yearlyRecaps(
            from: ledgers,
            unattributedIntervals: stored.unattributedIntervals
        )
        let expectedYearly = Dictionary(
            expectedYearlyRecaps.map { ($0.year, $0.recap.totalPlayDelta) },
            uniquingKeysWith: { _, latest in latest }
        )
        let actualYearly = Dictionary(
            stored.syncedYearlyRecaps.map { ($0.year, $0.recap.totalPlayDelta) },
            uniquingKeysWith: { _, latest in latest }
        )
        let yearlyTotalsMatch = expectedYearly == actualYearly
        let lastEvent = stored.reliabilityEvents.last
        let effectiveIntervals = Set(ledgers.map { calendar.recapYear(containing: $0.monthStart) })
            .flatMap { year in
                effectiveUnattributedIntervals(
                    for: year,
                    intervals: stored.unattributedIntervals,
                    monthlyRecaps: ledgers
                        .map { $0.monthlyRecap(artworkLookup: ArtworkLookup(sourceSongs: [])) }
                        .filter { calendar.recapYear(containing: $0.monthStart) == year }
                )
            }

        return RecapDiagnosticsReport(
            generatedAt: date,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            reliabilityPolicyVersion: stored.counterReliabilityPolicyVersion,
            totalStoredSnapshots: stored.snapshots.count,
            monthlyLedgerCount: ledgers.count,
            cloudSummaryCount: stored.syncedRecaps.count,
            duplicateMonthCount: duplicateMonthCount,
            yearlyTotalsMatchMonthlyLedgers: yearlyTotalsMatch,
            unattributedIntervalCount: effectiveIntervals.count,
            unattributedPlayDelta: effectiveIntervals.reduce(0) { $0 + $1.recap.totalPlayDelta },
            lastTrustedUpdate: stored.lastTrustedObservationAt ?? stored.snapshots.last?.capturedAt,
            lastRejectedObservation: lastEvent?.occurredAt,
            recentRejectedObservationCount: stored.reliabilityEvents.count,
            months: months
        )
    }

    private func recordLocked(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist],
        at capturedAt: Date,
        reason: RecapSnapshotReason,
        shouldCommit: @Sendable () -> Bool
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

        var previous = stored.snapshots.last(where: {
            $0.capturedAt < snapshot.capturedAt && $0.isSameDevice(as: snapshot)
        })
        if previous == nil,
           let legacyDeviceIdentifierToBridge,
           !legacyDeviceIdentifierToBridge.isEmpty {
            previous = stored.snapshots.last(where: {
                $0.capturedAt < snapshot.capturedAt &&
                    $0.deviceIdentifier == legacyDeviceIdentifierToBridge
            })
        }

        // MediaPlayer can temporarily return the same library with many counters
        // reset to zero while the device is offline. Persisting that observation
        // makes the later online values look like brand-new plays. Keep the last
        // trustworthy snapshot authoritative until the counters recover.
        if let previous {
            let regression = counterRegressionAssessment(snapshot, after: previous)
            let hasCoverageDrop = !hasComparableCoverage(previous, latest: snapshot)
            let isMissedMonthBaseline = isUnobservedMonthGap(
                from: previous.capturedAt,
                to: snapshot.capturedAt
            ) && hasComparableScanCount(previous, latest: snapshot)
            let shouldQuarantineCoverage = hasCoverageDrop && !isMissedMonthBaseline
            let confirmsCoverageChange = shouldQuarantineCoverage && confirmsStableCoverageChange(
                snapshot,
                in: stored
            )
            if regression.isLikelyTransient || (shouldQuarantineCoverage && !confirmsCoverageChange) {
                if shouldCommit() {
                    stored.reliabilityEvents.append(
                        ReliabilityEvent(
                            id: "\(capturedAt.timeIntervalSinceReferenceDate)-\(snapshot.counterSignature)",
                            occurredAt: capturedAt,
                            kind: shouldQuarantineCoverage ? .rejectedCoverageDrop : .rejectedCounterRegression,
                            coverageSignature: snapshot.coverageSignature,
                            scannedSongCount: songs.count,
                            comparableItemCount: regression.comparableItemCount,
                            regressedItemCount: regression.regressedItemCount,
                            previousComparablePlayCount: regression.previousComparablePlayCount,
                            regressedPlayCount: regression.regressedPlayCount
                        )
                    )
                    stored.reliabilityEvents = Array(stored.reliabilityEvents.suffix(20))
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


            if confirmsCoverageChange {
                var updated = stored
                updated.lastTrustedObservationAt = capturedAt
                updated.snapshots.append(snapshot)
                updated.snapshots = retainedCanonicalSnapshots(from: updated.snapshots, now: capturedAt)
                rebaseMonthlyLedger(in: &updated, current: snapshot)
                updated.snapshots = compactSnapshotsForLocalStorage(from: updated.snapshots)
                if shouldCommit() {
                    let didPersist = saveLocked(updated)
                    stored = updated
                    retireLegacyDeviceBridgeIfNeeded(
                        previous: previous,
                        current: snapshot,
                        didPersist: didPersist
                    )
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
        }

        if shouldAppend(snapshot, after: stored.snapshots.last) {
            var updated = stored
            updated.lastTrustedObservationAt = capturedAt
            updated.snapshots.append(snapshot)
            updated.snapshots = retainedCanonicalSnapshots(from: updated.snapshots, now: capturedAt)
            if let previous, isUnobservedMonthGap(from: previous.capturedAt, to: snapshot.capturedAt) {
                if let interval = unattributedInterval(
                    from: previous,
                    to: snapshot,
                    history: updated.snapshots
                ) {
                    updated.unattributedIntervals = Self.mergedUnattributedIntervals(
                        updated.unattributedIntervals + [interval]
                    )
                }
                updated.unattributedIntervals = durableUnattributedIntervals(updated.unattributedIntervals)
                establishMonthlyBaseline(in: &updated, current: snapshot)
            } else {
                updateIncrementalRecap(in: &updated, previous: previous, current: snapshot)
            }
            updated.snapshots = compactSnapshotsForLocalStorage(from: updated.snapshots)
            if shouldCommit() {
                let didPersist = saveLocked(updated)
                stored = updated
                retireLegacyDeviceBridgeIfNeeded(
                    previous: previous,
                    current: snapshot,
                    didPersist: didPersist
                )
            }
        } else if shouldCommit(), shouldPersistTrustedObservation(at: capturedAt, in: stored) {
            stored.lastTrustedObservationAt = capturedAt
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

    private func retireLegacyDeviceBridgeIfNeeded(
        previous: LibrarySnapshot?,
        current: LibrarySnapshot,
        didPersist: Bool
    ) {
        guard didPersist,
              let legacyDeviceIdentifierToBridge,
              previous?.deviceIdentifier == legacyDeviceIdentifierToBridge,
              current.deviceIdentifier == deviceIdentifier else {
            return
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyDeviceBridgeDefaultsKey)
    }

    private struct CounterRegressionAssessment {
        let comparableItemCount: Int
        let regressedItemCount: Int
        let previousComparablePlayCount: Int
        let regressedPlayCount: Int
        let isLikelyTransient: Bool
    }

    private func counterRegressionAssessment(
        _ snapshot: LibrarySnapshot,
        after previous: LibrarySnapshot
    ) -> CounterRegressionAssessment {
        let previousByID = Dictionary(uniqueKeysWithValues: previous.songs.map { ($0.id, $0) })
        var comparableItemCount = 0
        var regressedItemCount = 0
        var previousComparablePlayCount = 0
        var regressedPlayCount = 0

        for song in snapshot.songs {
            guard let prior = previousByID[song.id], prior.playCount > 0 else { continue }
            comparableItemCount += 1
            previousComparablePlayCount += prior.playCount

            guard song.playCount < prior.playCount else { continue }
            let dateAddedAdvanced = song.dateAdded.map { currentDate in
                guard let priorDate = prior.dateAdded else { return true }
                return currentDate.timeIntervalSince(priorDate) > 60
            } ?? false
            guard !dateAddedAdvanced else { continue }

            regressedItemCount += 1
            regressedPlayCount += prior.playCount - song.playCount
        }

        let isLikelyTransient: Bool
        if comparableItemCount >= 5, previousComparablePlayCount > 0 {
            let widespreadItemThreshold = max(5, Int(ceil(Double(comparableItemCount) * 0.05)))
            let materialPlayThreshold = max(100, Int(ceil(Double(previousComparablePlayCount) * 0.1)))
            isLikelyTransient = regressedItemCount >= widespreadItemThreshold &&
                regressedPlayCount >= materialPlayThreshold
        } else if comparableItemCount > 0, previousComparablePlayCount >= 10 {
            // A small library cannot meet the normal five-item threshold. A
            // collapse affecting every comparable item is still safer to hold
            // than to turn into false new plays when MediaPlayer recovers.
            let materialPlayThreshold = max(10, Int(ceil(Double(previousComparablePlayCount) * 0.5)))
            isLikelyTransient = regressedItemCount == comparableItemCount &&
                regressedPlayCount >= materialPlayThreshold
        } else {
            isLikelyTransient = false
        }

        return CounterRegressionAssessment(
            comparableItemCount: comparableItemCount,
            regressedItemCount: regressedItemCount,
            previousComparablePlayCount: previousComparablePlayCount,
            regressedPlayCount: regressedPlayCount,
            isLikelyTransient: isLikelyTransient
        )
    }

    private func isLikelyTransientCounterRegression(
        _ snapshot: LibrarySnapshot,
        after previous: LibrarySnapshot
    ) -> Bool {
        counterRegressionAssessment(snapshot, after: previous).isLikelyTransient
    }

    private func shouldPersistTrustedObservation(at capturedAt: Date, in stored: StoredSnapshots) -> Bool {
        if let lastRejected = stored.reliabilityEvents.last?.occurredAt,
           lastRejected > (stored.lastTrustedObservationAt ?? .distantPast) {
            return true
        }
        guard let lastTrusted = stored.lastTrustedObservationAt else { return true }
        return capturedAt.timeIntervalSince(lastTrusted) >= 5 * 60
    }

    private func shouldAppend(_ snapshot: LibrarySnapshot, after previous: LibrarySnapshot?) -> Bool {
        guard let previous else { return true }

        if snapshot.capturedAt.timeIntervalSince(previous.capturedAt) >= minimumSnapshotInterval {
            return true
        }

        return snapshot.counterSignature != previous.counterSignature
    }

    private func isUnobservedMonthGap(from start: Date, to end: Date) -> Bool {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let startMonth = calendar.recapMonthInterval(containing: start).start
        let endMonth = calendar.recapMonthInterval(containing: end).start
        return (gregorian.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0) > 1
    }

    private func retainedSnapshots(from snapshots: [LibrarySnapshot], now: Date) -> [LibrarySnapshot] {
        guard let cutoff = calendar.date(byAdding: .month, value: -retentionMonths, to: now) else {
            return snapshots
        }
        return snapshots.filter { $0.capturedAt >= cutoff }
    }

    private func durableUnattributedIntervals(
        _ intervals: [UnattributedRecapInterval]
    ) -> [UnattributedRecapInterval] {
        // Missed-gap deltas are the only evidence for that listening. Preserve
        // them for the lifetime of recap history, but cap ranking payloads so
        // historical yearly totals stay accurate without retaining raw scans.
        intervals.map { $0.compacted() }
    }

    private func retainedCanonicalSnapshots(from snapshots: [LibrarySnapshot], now: Date) -> [LibrarySnapshot] {
        canonicalSnapshots(retainedSnapshots(from: snapshots, now: now))
    }

    private func compactSnapshotsForLocalStorage(from snapshots: [LibrarySnapshot]) -> [LibrarySnapshot] {
        let canonical = canonicalSnapshots(snapshots)
        let streams = Dictionary(grouping: canonical) {
            $0.logicalDeviceKey(fallbackDeviceIdentifier: deviceIdentifier)
        }
        var compacted: [LibrarySnapshot] = []

        for stream in streams.values {
            let ordered = canonicalSnapshots(stream)
            guard let latest = ordered.last else { continue }
            let activeMonth = calendar.startOfMonth(containing: latest.capturedAt)
            let activeMonthBoundary = calendar.recapMonthInterval(containing: latest.capturedAt).start
            if let baseline = ordered.last(where: { $0.capturedAt < activeMonthBoundary }) {
                compacted.append(baseline)
            }
            let activeSnapshots = ordered.filter {
                calendar.startOfMonth(containing: $0.capturedAt) == activeMonth
            }
            if let first = activeSnapshots.first {
                compacted.append(first)
            }
            if let latest = activeSnapshots.last,
               latest.syncIdentifier != activeSnapshots.first?.syncIdentifier {
                compacted.append(latest)
            }
        }

        return canonicalSnapshots(compacted)
    }

    private func compactRetainedCanonicalSnapshots(in stored: inout StoredSnapshots, now: Date) -> Bool {
        let snapshots = retainedCanonicalSnapshots(from: stored.snapshots, now: now)
        let existingIDs = stored.snapshots.map(\.syncIdentifier)
        let compactedIDs = snapshots.map(\.syncIdentifier)
        guard existingIDs != compactedIDs else { return false }

        stored.snapshots = snapshots
        return true
    }

    private func compactSnapshotsForCloudSync(
        from snapshots: [LibrarySnapshot],
        currentDeviceIdentifier: String
    ) -> [LibrarySnapshot] {
        let retainedSnapshots = retainedCanonicalSnapshots(from: snapshots, now: Date())
        let streams = Dictionary(grouping: retainedSnapshots.sortedForSyncPayloads()) {
            $0.logicalDeviceKey(fallbackDeviceIdentifier: currentDeviceIdentifier)
        }

        var syncSnapshots: [LibrarySnapshot] = []
        for stream in streams.values {
            let ordered = canonicalSnapshots(stream)
            guard let latest = ordered.last else { continue }
            let latestMonth = calendar.startOfMonth(containing: latest.capturedAt)
            let latestMonthBoundary = calendar.recapMonthInterval(containing: latest.capturedAt).start
            let monthSnapshots = ordered.filter {
                calendar.startOfMonth(containing: $0.capturedAt) == latestMonth
            }
            if let baseline = ordered.last(where: { $0.capturedAt < latestMonthBoundary }) {
                syncSnapshots.append(baseline)
            }
            syncSnapshots.append(contentsOf: monthSnapshots)
        }

        return canonicalSnapshots(syncSnapshots)
    }

    private static func attachRecapSummariesToLatestPayload(
        _ payloads: [RecapSnapshotSyncPayload],
        encodedRecaps: Data?,
        encodedYearlyRecaps: Data?,
        encodedUnattributedIntervals: Data?,
        archiveReliabilityPolicyVersion: Int,
        archiveCapturedAt: Date
    ) -> [RecapSnapshotSyncPayload] {
        let hasArchive = encodedRecaps != nil || encodedYearlyRecaps != nil || encodedUnattributedIntervals != nil
        guard hasArchive else {
            return payloads
        }
        if payloads.isEmpty {
            return [RecapSnapshotSyncPayload(
                id: RecapSnapshotSyncPayload.manifestArchiveOnlyID,
                capturedAt: archiveCapturedAt,
                counterSignature: "",
                reliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion,
                archiveReliabilityPolicyVersion: archiveReliabilityPolicyVersion,
                encodedSnapshot: Data(),
                encodedRecaps: encodedRecaps,
                encodedYearlyRecaps: encodedYearlyRecaps,
                encodedUnattributedIntervals: encodedUnattributedIntervals
            )]
        }

        // Keep two compact archive copies so either edge of rolling snapshot
        // compaction can disappear without taking finalized recap history with it.
        let orderedPayloads = payloads.sorted {
            $0.capturedAt == $1.capturedAt ? $0.id < $1.id : $0.capturedAt < $1.capturedAt
        }
        let archivePayloadIDs = Set([orderedPayloads.first?.id, orderedPayloads.last?.id].compactMap { $0 })

        return payloads.map { payload in
            guard archivePayloadIDs.contains(payload.id) else {
                return RecapSnapshotSyncPayload(
                    id: payload.id,
                    capturedAt: payload.capturedAt,
                    counterSignature: payload.counterSignature,
                    reliabilityPolicyVersion: payload.reliabilityPolicyVersion,
                    archiveReliabilityPolicyVersion: nil,
                    encodedSnapshot: payload.encodedSnapshot
                )
            }
            let encodedSnapshot: Data
            if let encodedUnattributedIntervals,
               let snapshot = try? JSONDecoder.playCount.decode(
                   LibrarySnapshot.self,
                   from: payload.encodedSnapshot
               ),
               let enriched = try? JSONEncoder.playCount.encode(
                   LibrarySnapshot(
                       capturedAt: snapshot.capturedAt,
                       reason: snapshot.reason,
                       appVersion: snapshot.appVersion,
                       scannedSongCount: snapshot.scannedSongCount,
                       deviceIdentifier: snapshot.deviceIdentifier,
                       aggregateCounters: snapshot.aggregateCounters,
                       songs: snapshot.songs,
                       encodedUnattributedIntervals: encodedUnattributedIntervals
                   )
               ),
               enriched.count <= maxSyncPayloadBytes {
                encodedSnapshot = enriched
            } else {
                encodedSnapshot = payload.encodedSnapshot
            }

            return RecapSnapshotSyncPayload(
                id: payload.id,
                capturedAt: payload.capturedAt,
                counterSignature: payload.counterSignature,
                reliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion,
                archiveReliabilityPolicyVersion: archiveReliabilityPolicyVersion,
                encodedSnapshot: encodedSnapshot,
                encodedRecaps: encodedRecaps,
                encodedYearlyRecaps: encodedYearlyRecaps,
                encodedUnattributedIntervals: encodedUnattributedIntervals
            )
        }
    }

    private static func archiveReliabilityPolicyVersion(in stored: StoredSnapshots) -> Int {
        let monthlyVersions = stored.syncedRecaps.map { $0.reliabilityPolicyVersion ?? 0 }
        let yearlyVersions = stored.syncedYearlyRecaps.map { $0.recap.reliabilityPolicyVersion ?? 0 }
        return (monthlyVersions + yearlyVersions).min() ?? currentCounterReliabilityPolicyVersion
    }

    private static func archiveCapturedAt(in stored: StoredSnapshots) -> Date {
        let recapDates = stored.syncedRecaps.map(\.generatedAt) +
            stored.syncedYearlyRecaps.map(\.recap.generatedAt) +
            stored.unattributedIntervals.map(\.endedAt)
        return recapDates.max() ?? .distantPast
    }

    private func updateSyncedRecaps(
        in stored: inout StoredSnapshots,
        snapshots: [LibrarySnapshot],
        affectedMonthStarts: Set<Date>? = nil
    ) -> Bool {
        let generatedLedgers: [SyncedMonthlyRecap]
        if let affectedMonthStarts {
            generatedLedgers = affectedMonthStarts.compactMap { monthStart in
                let monthInterval = calendar.recapMonthInterval(containing: monthStart)
                guard snapshots.contains(where: {
                    monthInterval.contains($0.capturedAt)
                }) else { return nil }
                return SyncedMonthlyRecap(
                    recap: snapshotRecap(for: monthStart, snapshots: snapshots),
                    preservingAllRankings: true
                )
            }
        } else {
            generatedLedgers = fullMonthlyRecaps(from: snapshots).map {
                SyncedMonthlyRecap(recap: $0, preservingAllRankings: true)
            }
        }
        let startingLedgers = stored.monthlyLedgers.isEmpty ? stored.syncedRecaps : stored.monthlyLedgers
        let mergedLedgers = Self.mergedSyncedRecaps(startingLedgers + generatedLedgers)
        let generatedRecaps = generatedLedgers.map { $0.compacted() }
        let mergedRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps + generatedRecaps)
        let generatedYearlyRecaps = yearlyRecaps(
            from: mergedLedgers,
            unattributedIntervals: stored.unattributedIntervals
        )

        var didChange = false
        if mergedLedgers != stored.monthlyLedgers {
            stored.monthlyLedgers = mergedLedgers
            didChange = true
        }
        if mergedRecaps != stored.syncedRecaps {
            stored.syncedRecaps = mergedRecaps
            didChange = true
        }
        let mergedYearlyRecaps = Self.mergedSyncedYearlyRecaps(
            stored.syncedYearlyRecaps + generatedYearlyRecaps
        )
        if mergedYearlyRecaps != stored.syncedYearlyRecaps {
            // A remote/archive year may be the only surviving evidence even when
            // this device has no (or only partial) monthly ledgers for that year.
            stored.syncedYearlyRecaps = mergedYearlyRecaps
            didChange = true
        }
        return didChange
    }

    /// Advances the active month's recap from one observation to the next. The
    /// full monthly ranking ledger is the durable accumulator, so a refresh is
    /// O(library size) and never replays the month's historical observations.
    private func updateIncrementalRecap(
        in stored: inout StoredSnapshots,
        previous: LibrarySnapshot?,
        current: LibrarySnapshot,
        rebuildYearly: Bool = true
    ) {
        let monthStart = calendar.startOfMonth(containing: current.capturedAt)
        let monthInterval = calendar.recapMonthInterval(containing: current.capturedAt)
        let calculationMonthStart = monthInterval.start
        let monthEnd = monthInterval.end
        var existing = stored.monthlyLedgers
            .filter { $0.monthStart == monthStart }
            .sorted(by: Self.isHigherPrioritySyncedRecap)
            .first
        let bridgesLegacyUpgrade = legacyDeviceIdentifierToBridge != nil &&
            previous?.deviceIdentifier == legacyDeviceIdentifierToBridge &&
            current.deviceIdentifier == deviceIdentifier

        guard existing != nil,
              let previous,
              previous.isSameDevice(as: current) || bridgesLegacyUpgrade,
              hasComparableCoverage(previous, latest: current) else {
            _ = updateSyncedRecaps(
                in: &stored,
                snapshots: stored.snapshots,
                affectedMonthStarts: Set([monthStart])
            )
            return
        }

        if let disconnected = existing,
           abs(disconnected.generatedAt.timeIntervalSince(previous.capturedAt)) >= 0.001 {
            let disconnectedRecap = disconnected.monthlyRecap(
                artworkLookup: ArtworkLookup(sourceSongs: [])
            )
            let rebuiltRecap = snapshotRecap(for: monthStart, snapshots: stored.snapshots)
            guard current.capturedAt > disconnected.generatedAt else {
                _ = updateSyncedRecaps(
                    in: &stored,
                    snapshots: stored.snapshots,
                    affectedMonthStarts: Set([monthStart])
                )
                return
            }
            guard isHigherPriorityDisplayRecap(disconnectedRecap, than: rebuiltRecap) else {
                _ = updateSyncedRecaps(
                    in: &stored,
                    snapshots: stored.snapshots,
                    affectedMonthStarts: Set([monthStart])
                )
                return
            }

            // A current-policy Cloud summary can legitimately outrank the raw
            // snapshots on this device while still being disconnected from their
            // capture chain. Rebuilding and merging repeats that same winner on
            // every refresh, leaving the recap frozen forever. Preserve the
            // durable total, but reconnect it only to a trustworthy comparable
            // local observation. If that observation follows the archive, its
            // next interval is safe to count; otherwise establish a fresh anchor
            // and wait for the next proven delta rather than risking overlap.
            if previous.capturedAt > disconnected.generatedAt,
               monthInterval.contains(previous.capturedAt) {
                rebaseMonthlyLedger(in: &stored, current: previous, rebuildYearly: false)
                existing = stored.monthlyLedgers
                    .filter { $0.monthStart == monthStart }
                    .sorted(by: Self.isHigherPrioritySyncedRecap)
                    .first
            } else {
                rebaseMonthlyLedger(in: &stored, current: current, rebuildYearly: rebuildYearly)
                return
            }
        }

        guard let existing else {
            _ = updateSyncedRecaps(
                in: &stored,
                snapshots: stored.snapshots,
                affectedMonthStarts: Set([monthStart])
            )
            return
        }

        let priorRecap = existing.monthlyRecap(artworkLookup: ArtworkLookup(sourceSongs: []))
        let resolver = RecordingIdentityResolver(snapshots: [previous, current])
        let previousByID = Dictionary(uniqueKeysWithValues: previous.songs.map { ($0.id, $0) })
        let previousRecordingIdentities = Set(previous.songs.map { resolver.identity(for: $0) })

        var existingSongsByIdentity: [String: MonthlyRecap.RankedSong] = [:]
        var legacyIdentities: [String: Set<String>] = [:]
        for song in priorRecap.topSongs {
            let identity = song.recordingIdentity ?? legacyRecapRecordingIdentity(
                title: song.title,
                artist: song.artist,
                albumTitle: song.albumTitle
            )
            existingSongsByIdentity[identity] = song
            legacyIdentities[legacyRecapRecordingIdentity(
                title: song.title,
                artist: song.artist,
                albumTitle: song.albumTitle
            ), default: []].insert(identity)
        }

        func accumulatedIdentity(for song: SongSnapshot) -> String {
            let resolved = resolver.identity(for: song)
            if existingSongsByIdentity[resolved] != nil { return resolved }
            if let storeID = song.playbackStoreID {
                let storeIdentity = "store:\(storeID)"
                if existingSongsByIdentity[storeIdentity] != nil { return storeIdentity }
            }
            let legacy = legacyRecapRecordingIdentity(
                title: song.title,
                artist: song.artist,
                albumTitle: song.albumTitle
            )
            if let identities = legacyIdentities[legacy], identities.count == 1,
               let identity = identities.first {
                return identity
            }
            return resolved
        }

        var intervalDeltas: [SongDelta] = []
        var hasCounterDiscontinuity = false
        for song in current.songs {
            let identity = accumulatedIdentity(for: song)
            let wasAddedThisMonth = song.dateAdded.map { $0 >= calculationMonthStart && $0 < monthEnd } ?? false
            let playDelta: Int
            let skipDelta: Int

            if let prior = previousByID[song.id] {
                let dateAddedAdvanced = song.dateAdded.map { currentDate in
                    guard currentDate >= calculationMonthStart && currentDate < monthEnd else { return false }
                    guard let priorDate = prior.dateAdded else { return true }
                    return currentDate.timeIntervalSince(priorDate) > 60
                } ?? false
                if song.playCount >= prior.playCount {
                    playDelta = song.playCount - prior.playCount
                    skipDelta = max(0, song.skipCount - prior.skipCount)
                } else if dateAddedAdvanced {
                    playDelta = song.playCount
                    skipDelta = song.skipCount
                    hasCounterDiscontinuity = true
                } else {
                    // Apple can temporarily report a lower counter. Do not erase
                    // or double-count until a reset is supported by dateAdded.
                    playDelta = 0
                    skipDelta = 0
                }
            } else if existingSongsByIdentity[identity] != nil || wasAddedThisMonth {
                // A different persistent ID for a known recording is the normal
                // delete/re-add shape. Its new counter is a fresh epoch.
                playDelta = song.playCount
                skipDelta = song.skipCount
                hasCounterDiscontinuity = existingSongsByIdentity[identity] != nil ||
                    previousRecordingIdentities.contains(identity)
            } else {
                playDelta = 0
                skipDelta = 0
            }

            guard playDelta > 0 || skipDelta > 0 else { continue }
            intervalDeltas.append(
                SongDelta(
                    latest: song,
                    playDelta: playDelta,
                    skipDelta: skipDelta,
                    recordingIdentity: identity,
                    playbackStoreID: song.playbackStoreID,
                    isNewSong: wasAddedThisMonth && existingSongsByIdentity[identity] == nil
                )
            )
        }

        let aggregatePlayDelta = current.aggregateCounters.flatMap { currentCounters in
            previous.aggregateCounters.map { previousCounters in
                max(0, currentCounters.playCount - previousCounters.playCount)
            }
        }
        let aggregateSkipDelta = current.aggregateCounters.flatMap { currentCounters in
            previous.aggregateCounters.map { previousCounters in
                max(0, currentCounters.skipCount - previousCounters.skipCount)
            }
        }
        let aggregateListeningDelta = current.aggregateCounters.flatMap { currentCounters in
            previous.aggregateCounters.map { previousCounters in
                max(0, currentCounters.listeningDuration - previousCounters.listeningDuration)
            }
        }
        let rawIntervalDeltas = intervalDeltas
        if !hasCounterDiscontinuity {
            intervalDeltas = rankingDeltas(
                from: intervalDeltas,
                monthStart: calculationMonthStart,
                monthEnd: monthEnd,
                aggregatePlayDelta: aggregatePlayDelta
            )
        }

        var songsByIdentity = existingSongsByIdentity
        for delta in intervalDeltas {
            let old = songsByIdentity[delta.recordingIdentity]
            songsByIdentity[delta.recordingIdentity] = MonthlyRecap.RankedSong(
                id: delta.latest.id,
                title: delta.latest.title,
                artist: delta.latest.artist,
                albumTitle: delta.latest.albumTitle,
                playDelta: (old?.playDelta ?? 0) + delta.playDelta,
                skipDelta: (old?.skipDelta ?? 0) + delta.skipDelta,
                listeningDuration: (old?.listeningDuration ?? 0) + delta.listeningDuration,
                artwork: nil,
                recordingIdentity: delta.recordingIdentity,
                playbackStoreID: delta.playbackStoreID ?? old?.playbackStoreID
            )
        }
        let rankedSongs = songsByIdentity.values.sorted {
            if $0.playDelta != $1.playDelta { return $0.playDelta > $1.playDelta }
            if $0.listeningDuration != $1.listeningDuration { return $0.listeningDuration > $1.listeningDuration }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        var artists = Dictionary(uniqueKeysWithValues: priorRecap.topArtists.map { ($0.id, $0) })
        var albums = Dictionary(uniqueKeysWithValues: priorRecap.topAlbums.map { ($0.id, $0) })
        for delta in intervalDeltas where delta.playDelta > 0 {
            let artistID = artistGroupID(for: delta)
            let oldArtist = artists[artistID]
            artists[artistID] = MonthlyRecap.RankedGroup(
                id: artistID,
                title: delta.latest.artist,
                subtitle: "Artist",
                playDelta: (oldArtist?.playDelta ?? 0) + delta.playDelta,
                listeningDuration: (oldArtist?.listeningDuration ?? 0) + delta.listeningDuration,
                artwork: nil
            )
            let albumID = albumGroupID(for: delta)
            let oldAlbum = albums[albumID]
            albums[albumID] = MonthlyRecap.RankedGroup(
                id: albumID,
                title: delta.latest.albumTitle,
                subtitle: delta.latest.albumArtist,
                playDelta: (oldAlbum?.playDelta ?? 0) + delta.playDelta,
                listeningDuration: (oldAlbum?.listeningDuration ?? 0) + delta.listeningDuration,
                artwork: nil
            )
        }

        var newSongIdentities = Set(priorRecap.topNewSongs.map {
            $0.recordingIdentity ?? legacyRecapRecordingIdentity(
                title: $0.title,
                artist: $0.artist,
                albumTitle: $0.albumTitle
            )
        })
        newSongIdentities.formUnion(intervalDeltas.filter(\.isNewSong).map(\.recordingIdentity))
        let topNewSongs = rankedSongs.filter { song in
            let identity = song.recordingIdentity ?? legacyRecapRecordingIdentity(
                title: song.title,
                artist: song.artist,
                albumTitle: song.albumTitle
            )
            return newSongIdentities.contains(identity)
        }

        let songPlayDelta = rawIntervalDeltas.reduce(0) { $0 + $1.playDelta }
        let songSkipDelta = rawIntervalDeltas.reduce(0) { $0 + $1.skipDelta }
        let songListeningDuration = rawIntervalDeltas.reduce(0) { $0 + $1.listeningDuration }
        let intervalPlayDelta = hasCounterDiscontinuity ? songPlayDelta : aggregatePlayDelta ?? songPlayDelta
        let intervalSkipDelta = hasCounterDiscontinuity ? songSkipDelta : aggregateSkipDelta ?? songSkipDelta
        let intervalListeningDuration = hasCounterDiscontinuity
            ? songListeningDuration
            : aggregateListeningDelta ?? songListeningDuration
        let orderedSnapshots = stored.snapshots.sorted { $0.capturedAt < $1.capturedAt }
        let inMonthSnapshots = orderedSnapshots.filter { monthInterval.contains($0.capturedAt) }
        let movementBaseline = baselineSnapshot(
            for: current,
            inMonth: inMonthSnapshots,
            ordered: orderedSnapshots,
            monthStart: calculationMonthStart
        )
        let currentByIdentity = Dictionary(
            current.songs.map { (accumulatedIdentity(for: $0), $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let monthToDateDeltas = rankedSongs.compactMap { ranked -> SongDelta? in
            let identity = ranked.recordingIdentity ?? legacyRecapRecordingIdentity(
                title: ranked.title, artist: ranked.artist, albumTitle: ranked.albumTitle
            )
            guard ranked.playDelta > 0, let song = currentByIdentity[identity] else { return nil }
            return SongDelta(latest: song, playDelta: ranked.playDelta, skipDelta: ranked.skipDelta,
                             recordingIdentity: identity, playbackStoreID: ranked.playbackStoreID, isNewSong: false)
        }
        let artworkLookup = ArtworkLookup(sourceSongs: [])
        let biggestGainers = movementSongs(from: monthToDateDeltas, baseline: movementBaseline, latest: current, artworkLookup: artworkLookup)
        let biggestAlbumGainers = movementGroups(
            from: monthToDateDeltas, baseline: movementBaseline, latest: current, id: albumGroupID,
            snapshotID: albumGroupID,
            title: { $0.latest.albumTitle }, subtitle: { $0.latest.albumArtist }, artwork: { _ in nil }
        )
        let biggestArtistGainers = movementGroups(
            from: monthToDateDeltas, baseline: movementBaseline, latest: current, id: artistGroupID,
            snapshotID: artistGroupID,
            title: { $0.latest.artist }, subtitle: { _ in "Artist" }, artwork: { _ in nil }
        )
        let recap = MonthlyRecap(
            monthStart: monthStart,
            generatedAt: current.capturedAt,
            lastCaptureReason: current.reason,
            trackingStart: priorRecap.trackingStart ?? previous.capturedAt,
            snapshotCount: priorRecap.snapshotCount + 1,
            totalPlayDelta: priorRecap.totalPlayDelta + intervalPlayDelta,
            totalSkipDelta: priorRecap.totalSkipDelta + intervalSkipDelta,
            totalListeningDuration: priorRecap.totalListeningDuration + intervalListeningDuration,
            playedSongCount: rankedSongs.filter { $0.playDelta > 0 }.count,
            newSongCount: max(
                priorRecap.newSongCount,
                current.aggregateCounters?.monthNewSongCount ?? topNewSongs.count
            ),
            topSongs: rankedSongs,
            topArtists: artists.values.sorted { $0.playDelta > $1.playDelta },
            topAlbums: albums.values.sorted { $0.playDelta > $1.playDelta },
            biggestGainers: biggestGainers,
            biggestAlbumGainers: biggestAlbumGainers,
            biggestArtistGainers: biggestArtistGainers,
            topNewSongs: topNewSongs
        )
        guard isPlausibleListeningDuration(
            recap.totalListeningDuration,
            monthStart: calculationMonthStart,
            baseline: previous,
            latest: current
        ) else {
            _ = updateSyncedRecaps(
                in: &stored,
                snapshots: stored.snapshots,
                affectedMonthStarts: Set([monthStart])
            )
            return
        }
        let ledger = SyncedMonthlyRecap(recap: recap, preservingAllRankings: true)
        stored.monthlyLedgers.removeAll { $0.monthStart == monthStart }
        stored.monthlyLedgers.append(ledger)
        stored.monthlyLedgers.sort { $0.monthStart < $1.monthStart }
        stored.syncedRecaps.removeAll { $0.monthStart == monthStart }
        stored.syncedRecaps.append(ledger.compacted())
        stored.syncedRecaps.sort { $0.monthStart < $1.monthStart }
        if rebuildYearly {
            stored.syncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(
                stored.syncedYearlyRecaps + yearlyRecaps(
                    from: stored.monthlyLedgers,
                    unattributedIntervals: stored.unattributedIntervals
                )
            )
        }
    }

    private func establishMonthlyBaseline(
        in stored: inout StoredSnapshots,
        current: LibrarySnapshot,
        rebuildYearly: Bool = true
    ) {
        let monthStart = calendar.startOfMonth(containing: current.capturedAt)
        let baseline = MonthlyRecap(
            monthStart: monthStart,
            generatedAt: current.capturedAt,
            lastCaptureReason: current.reason,
            trackingStart: current.capturedAt,
            snapshotCount: 1,
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
        let fullBaseline = SyncedMonthlyRecap(recap: baseline, preservingAllRankings: true)
        let compactBaseline = fullBaseline.compacted()
        stored.monthlyLedgers = Self.mergedSyncedRecaps(stored.monthlyLedgers + [fullBaseline])
        stored.syncedRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps + [compactBaseline])
        if rebuildYearly {
            stored.syncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(
                stored.syncedYearlyRecaps + yearlyRecaps(
                    from: stored.monthlyLedgers,
                    unattributedIntervals: stored.unattributedIntervals
                )
            )
        }
    }

    /// Promotes a repeatedly observed library-size change without attributing
    /// the newly visible or missing counters as listening. Existing month-to-date
    /// totals remain intact and this observation becomes the baseline for later
    /// deltas.
    private func rebaseMonthlyLedger(
        in stored: inout StoredSnapshots,
        current: LibrarySnapshot,
        rebuildYearly: Bool = true
    ) {
        let monthStart = calendar.startOfMonth(containing: current.capturedAt)
        guard let existing = stored.monthlyLedgers
            .filter({ $0.monthStart == monthStart })
            .sorted(by: Self.isHigherPrioritySyncedRecap)
            .first else {
            establishMonthlyBaseline(in: &stored, current: current)
            return
        }

        let recap = existing
            .monthlyRecap(artworkLookup: ArtworkLookup(sourceSongs: []))
            .rebased(at: current.capturedAt, reason: current.reason)
        let ledger = SyncedMonthlyRecap(recap: recap, preservingAllRankings: true)
        stored.monthlyLedgers.removeAll { $0.monthStart == monthStart }
        stored.monthlyLedgers.append(ledger)
        stored.monthlyLedgers.sort { $0.monthStart < $1.monthStart }
        stored.syncedRecaps.removeAll { $0.monthStart == monthStart }
        stored.syncedRecaps.append(ledger.compacted())
        stored.syncedRecaps.sort { $0.monthStart < $1.monthStart }
        if rebuildYearly {
            stored.syncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(
                stored.syncedYearlyRecaps + yearlyRecaps(
                    from: stored.monthlyLedgers,
                    unattributedIntervals: stored.unattributedIntervals
                )
            )
        }
    }

    private func unattributedInterval(
        from previous: LibrarySnapshot,
        to current: LibrarySnapshot,
        history: [LibrarySnapshot]
    ) -> UnattributedRecapInterval? {
        guard previous.isSameDevice(as: current),
              hasComparableCoverage(previous, latest: current) else {
            return nil
        }

        let intervalEnd = current.capturedAt.addingTimeInterval(0.001)
        let epochAnalysis = counterEpochAnalysis(
            baseline: previous,
            inMonth: [current],
            latest: current,
            history: history,
            monthStart: previous.capturedAt,
            monthEnd: intervalEnd
        )
        let aggregate = aggregateDeltas(
            latest: current,
            baseline: previous,
            counterEpochAnalysis: epochAnalysis
        )
        let rankedDeltas = rankingDeltas(
            from: epochAnalysis.deltas.filter { $0.playDelta > 0 },
            monthStart: previous.capturedAt,
            monthEnd: intervalEnd,
            aggregatePlayDelta: aggregate?.playDelta
        )
        let totalPlayDelta = aggregate?.playDelta ?? epochAnalysis.deltas.reduce(0) { $0 + $1.playDelta }
        let totalSkipDelta = aggregate?.skipDelta ?? epochAnalysis.deltas.reduce(0) { $0 + $1.skipDelta }
        let totalListeningDuration = aggregate?.listeningDuration
            ?? epochAnalysis.deltas.reduce(0) { $0 + $1.listeningDuration }
        guard totalPlayDelta > 0 || totalSkipDelta > 0 else { return nil }

        let artworkLookup = ArtworkLookup(sourceSongs: [])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let recapYearStart = utc.date(from: DateComponents(
            timeZone: utc.timeZone,
            year: calendar.recapYear(containing: current.capturedAt),
            month: 1,
            day: 1,
            hour: 12
        )) ?? calendar.startOfMonth(containing: current.capturedAt)
        let recap = MonthlyRecap(
            monthStart: recapYearStart,
            generatedAt: current.capturedAt,
            lastCaptureReason: current.reason,
            trackingStart: previous.capturedAt,
            snapshotCount: 2,
            totalPlayDelta: totalPlayDelta,
            totalSkipDelta: totalSkipDelta,
            totalListeningDuration: totalListeningDuration,
            playedSongCount: rankedDeltas.count,
            newSongCount: 0,
            topSongs: rankedDeltas.sorted(by: compareDeltas).map {
                rankedSong(from: $0, artworkLookup: artworkLookup)
            },
            topArtists: groupedDeltas(
                rankedDeltas,
                id: artistGroupID,
                title: { $0.latest.artist },
                subtitle: { _ in "Artist" },
                artwork: { _ in nil }
            ),
            topAlbums: groupedDeltas(
                rankedDeltas,
                id: albumGroupID,
                title: { $0.latest.albumTitle },
                subtitle: { $0.latest.albumArtist },
                artwork: { _ in nil }
            ),
            biggestGainers: [],
            topNewSongs: [],
            unattributedPlayDelta: totalPlayDelta,
            unattributedListeningDuration: totalListeningDuration
        )
        return UnattributedRecapInterval(
            startedAt: previous.capturedAt,
            endedAt: current.capturedAt,
            deviceIdentifier: current.deviceIdentifier ?? deviceIdentifier,
            recap: recap
        )
    }

    private func syncedRecaps(from snapshots: [LibrarySnapshot]) -> [SyncedMonthlyRecap] {
        fullMonthlyRecaps(from: snapshots).map { SyncedMonthlyRecap(recap: $0) }
    }

    private func fullMonthlyRecaps(from snapshots: [LibrarySnapshot]) -> [MonthlyRecap] {
        let monthStarts = Set(snapshots.map { calendar.startOfMonth(containing: $0.capturedAt) })
        return monthStarts.map { monthStart in
            snapshotRecap(for: monthStart, snapshots: snapshots)
        }
    }

    private func yearlyRecaps(
        from syncedRecaps: [SyncedMonthlyRecap],
        unattributedIntervals: [UnattributedRecapInterval]
    ) -> [SyncedYearlyRecap] {
        let artworkLookup = ArtworkLookup(sourceSongs: [])
        let monthlyRecaps = syncedRecaps.map { $0.monthlyRecap(artworkLookup: artworkLookup) }
        let monthlyRecapsByYear = Dictionary(grouping: monthlyRecaps) {
            calendar.recapYear(containing: $0.monthStart)
        }
        let policyVersionsByYear = Dictionary(grouping: syncedRecaps) {
            calendar.recapYear(containing: $0.monthStart)
        }.mapValues { recaps in
            recaps.map { $0.reliabilityPolicyVersion ?? 0 }.min() ?? 0
        }

        return monthlyRecapsByYear.map { year, recaps in
            let months = recaps.map(\.monthStart).sorted()
            let fallbackMonth = months.first ?? calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
            let gapRecaps = effectiveUnattributedIntervals(
                for: year,
                intervals: unattributedIntervals,
                monthlyRecaps: recaps
            ).map { $0.monthlyRecap(artworkLookup: artworkLookup) }
            let yearlyRecap = MonthlyRecap.yearly(
                for: year,
                months: months,
                monthlyRecaps: recaps + gapRecaps,
                fallbackMonth: fallbackMonth,
                fallbackRecap: .empty(for: fallbackMonth, calendar: calendar)
            )
            return SyncedYearlyRecap(
                year: year,
                recap: yearlyRecap,
                reliabilityPolicyVersion: policyVersionsByYear[year] ?? 0
            )
        }
    }

    private func effectiveUnattributedIntervals(
        for year: Int,
        intervals: [UnattributedRecapInterval],
        monthlyRecaps: [MonthlyRecap]
    ) -> [UnattributedRecapInterval] {
        let sameYear = intervals.filter {
            calendar.recapYear(containing: $0.startedAt) == year &&
                calendar.recapYear(containing: $0.endedAt) == year
        }.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.endedAt < $1.endedAt
        }

        var nonOverlapping: [UnattributedRecapInterval] = []
        for interval in sameYear {
            guard let index = nonOverlapping.firstIndex(where: {
                $0.startedAt < interval.endedAt && interval.startedAt < $0.endedAt
            }) else {
                nonOverlapping.append(interval)
                continue
            }
            if Self.isHigherPrioritySyncedRecap(interval.recap, than: nonOverlapping[index].recap) {
                nonOverlapping[index] = interval
            }
        }

        return nonOverlapping.filter { interval in
            !isFullyCovered(
                from: interval.startedAt,
                through: interval.endedAt,
                by: monthlyRecaps
            )
        }
    }

    private func isFullyCovered(
        from start: Date,
        through end: Date,
        by monthlyRecaps: [MonthlyRecap]
    ) -> Bool {
        let coverage = monthlyRecaps.compactMap { recap -> (Date, Date)? in
            guard let trackingStart = recap.trackingStart,
                  recap.generatedAt > trackingStart else {
                return nil
            }
            let lower = max(start, trackingStart)
            let upper = min(end, recap.generatedAt)
            return lower < upper ? (lower, upper) : nil
        }.sorted { $0.0 < $1.0 }

        var coveredThrough = start
        for range in coverage {
            guard range.0 <= coveredThrough.addingTimeInterval(1) else { return false }
            coveredThrough = max(coveredThrough, range.1)
            if coveredThrough >= end { return true }
        }
        return false
    }

    private static func encodedSyncedRecaps(_ recaps: [SyncedMonthlyRecap]) -> Data? {
        guard !recaps.isEmpty else { return nil }
        return try? JSONEncoder.playCount.encode(recaps)
    }

    private static func encodedSyncedYearlyRecaps(_ recaps: [SyncedYearlyRecap]) -> Data? {
        guard !recaps.isEmpty else { return nil }
        return try? JSONEncoder.playCount.encode(recaps)
    }

    private static func encodedUnattributedIntervals(_ intervals: [UnattributedRecapInterval]) -> Data? {
        guard !intervals.isEmpty else { return nil }
        return try? JSONEncoder.playCount.encode(intervals.map { $0.compacted() })
    }

    static func mergedArchiveEvidence(
        existingRecaps: Data?,
        existingYearlyRecaps: Data?,
        existingUnattributedIntervals: Data?,
        localRecaps: Data?,
        localYearlyRecaps: Data?,
        localUnattributedIntervals: Data?,
        preferLocalFallback: Bool
    ) -> RecapArchiveEvidenceData {
        func monthly(from data: Data?) -> [SyncedMonthlyRecap]? {
            guard let data else { return [] }
            if let summaries = try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: data) {
                return summaries.monthlyRecaps
            }
            return try? JSONDecoder.playCount.decode([SyncedMonthlyRecap].self, from: data)
        }
        func yearly(from data: Data?) -> [SyncedYearlyRecap]? {
            guard let data else { return [] }
            return try? JSONDecoder.playCount.decode([SyncedYearlyRecap].self, from: data)
        }
        func intervals(from data: Data?) -> [UnattributedRecapInterval]? {
            guard let data else { return [] }
            return try? JSONDecoder.playCount.decode([UnattributedRecapInterval].self, from: data)
        }
        func fallback(_ existing: Data?, _ local: Data?) -> Data? {
            preferLocalFallback ? (local ?? existing) : (existing ?? local)
        }

        let existingMonthly = monthly(from: existingRecaps)
        let localMonthly = monthly(from: localRecaps)
        let mergedMonthly = existingMonthly.flatMap { existing in
            localMonthly.map { mergedSyncedRecaps(existing + $0) }
        }
        let existingYearly = yearly(from: existingYearlyRecaps)
        let localYearly = yearly(from: localYearlyRecaps)
        let mergedYearly = existingYearly.flatMap { existing in
            localYearly.map { mergedSyncedYearlyRecaps(existing + $0) }
        }
        let existingIntervals = intervals(from: existingUnattributedIntervals)
        let localIntervals = intervals(from: localUnattributedIntervals)
        let mergedIntervals = existingIntervals.flatMap { existing in
            localIntervals.map { mergedUnattributedIntervals(existing + $0) }
        }
        let policies = (mergedMonthly ?? []).map { $0.reliabilityPolicyVersion ?? 0 } +
            (mergedYearly ?? []).map { $0.recap.reliabilityPolicyVersion ?? 0 }

        return RecapArchiveEvidenceData(
            encodedRecaps: mergedMonthly.flatMap(encodedSyncedRecaps) ?? fallback(existingRecaps, localRecaps),
            encodedYearlyRecaps: mergedYearly.flatMap(encodedSyncedYearlyRecaps) ??
                fallback(existingYearlyRecaps, localYearlyRecaps),
            encodedUnattributedIntervals: mergedIntervals.flatMap(encodedUnattributedIntervals) ??
                fallback(existingUnattributedIntervals, localUnattributedIntervals),
            minimumReliabilityPolicyVersion: policies.min()
        )
    }

    static func isValidArchiveEvidence(
        encodedRecaps: Data?,
        encodedYearlyRecaps: Data?,
        encodedUnattributedIntervals: Data?
    ) -> Bool {
        isValidMonthlyArchiveEvidence(encodedRecaps) &&
            isValidYearlyArchiveEvidence(encodedYearlyRecaps) &&
            isValidUnattributedArchiveEvidence(encodedUnattributedIntervals)
    }

    static func isValidMonthlyArchiveEvidence(_ data: Data?) -> Bool {
        guard let data else { return true }
        return (try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: data)) != nil ||
            (try? JSONDecoder.playCount.decode([SyncedMonthlyRecap].self, from: data)) != nil
    }

    static func isValidYearlyArchiveEvidence(_ data: Data?) -> Bool {
        guard let data else { return true }
        return (try? JSONDecoder.playCount.decode([SyncedYearlyRecap].self, from: data)) != nil
    }

    static func isValidUnattributedArchiveEvidence(_ data: Data?) -> Bool {
        guard let data else { return true }
        return (try? JSONDecoder.playCount.decode([UnattributedRecapInterval].self, from: data)) != nil
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

    private static func unattributedIntervals(
        from payload: RecapSnapshotSyncPayload
    ) -> [UnattributedRecapInterval] {
        let embeddedData = (try? JSONDecoder.playCount.decode(
            LibrarySnapshot.self,
            from: payload.encodedSnapshot
        ))?.encodedUnattributedIntervals
        guard let data = payload.encodedUnattributedIntervals ?? embeddedData else { return [] }
        return (try? JSONDecoder.playCount.decode([UnattributedRecapInterval].self, from: data)) ?? []
    }

    private static func mergedSyncedRecaps(_ recaps: [SyncedMonthlyRecap]) -> [SyncedMonthlyRecap] {
        var recapsByMonth: [Date: SyncedMonthlyRecap] = [:]
        for recap in recaps {
            let canonicalMonthStart = canonicalPersistedMonthStart(recap.monthStart)
            let canonicalRecap = normalizedSyncedRecap(
                recap,
                monthStart: canonicalMonthStart,
                reliabilityPolicyVersion: recap.reliabilityPolicyVersion,
                preservingAllRankings: true
            )
            guard let existing = recapsByMonth[canonicalMonthStart] else {
                recapsByMonth[canonicalMonthStart] = canonicalRecap
                continue
            }

            if isHigherPrioritySyncedRecap(canonicalRecap, than: existing) {
                recapsByMonth[canonicalMonthStart] = canonicalRecap
            }
        }

        return recapsByMonth.values.sorted {
            if $0.monthStart != $1.monthStart {
                return $0.monthStart < $1.monthStart
            }
            return $0.generatedAt < $1.generatedAt
        }
    }

    private static func normalizedSyncedRecap(
        _ recap: SyncedMonthlyRecap,
        monthStart: Date,
        reliabilityPolicyVersion: Int?,
        preservingAllRankings: Bool
    ) -> SyncedMonthlyRecap {
        let normalized = recap.monthlyRecap(
            artworkLookup: ArtworkLookup(sourceSongs: [])
        ).replacingMonthStart(monthStart)
        return SyncedMonthlyRecap(
            recap: normalized,
            preservingAllRankings: preservingAllRankings,
            reliabilityPolicyVersion: reliabilityPolicyVersion
        )
    }

    /// Legacy month starts were encoded as local midnight. Moving between time
    /// zones therefore created several absolute Dates for the same logical month.
    /// Choose the nearest UTC month boundary, then store the month at UTC noon so
    /// it remains in the same calendar month in every supported time zone.
    private static func canonicalPersistedMonthStart(_ date: Date) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        let components = utc.dateComponents([.year, .month], from: date)
        guard let currentBoundary = utc.date(from: DateComponents(
            timeZone: utc.timeZone,
            year: components.year,
            month: components.month,
            day: 1
        )),
        let nextBoundary = utc.date(byAdding: .month, value: 1, to: currentBoundary) else {
            return date
        }

        let nearestBoundary = abs(date.timeIntervalSince(currentBoundary)) <= abs(date.timeIntervalSince(nextBoundary))
            ? currentBoundary
            : nextBoundary
        let nearestComponents = utc.dateComponents([.year, .month], from: nearestBoundary)
        return utc.date(from: DateComponents(
            timeZone: utc.timeZone,
            year: nearestComponents.year,
            month: nearestComponents.month,
            day: 1,
            hour: 12
        )) ?? nearestBoundary
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

    private static func mergedUnattributedIntervals(
        _ intervals: [UnattributedRecapInterval]
    ) -> [UnattributedRecapInterval] {
        var intervalsByID: [String: UnattributedRecapInterval] = [:]
        for interval in intervals {
            guard let existing = intervalsByID[interval.id] else {
                intervalsByID[interval.id] = interval
                continue
            }
            if isHigherPrioritySyncedRecap(interval.recap, than: existing.recap) {
                intervalsByID[interval.id] = interval
            }
        }
        return intervalsByID.values.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            if $0.endedAt != $1.endedAt { return $0.endedAt < $1.endedAt }
            return $0.id < $1.id
        }
    }

    private static func isHigherPrioritySyncedRecap(_ lhs: SyncedMonthlyRecap, than rhs: SyncedMonthlyRecap) -> Bool {
        let lhsPolicyVersion = lhs.reliabilityPolicyVersion ?? 0
        let rhsPolicyVersion = rhs.reliabilityPolicyVersion ?? 0
        if lhsPolicyVersion != rhsPolicyVersion {
            return lhsPolicyVersion > rhsPolicyVersion
        }

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

        let lhsUnattributed = lhs.unattributedPlayDelta ?? 0
        let rhsUnattributed = rhs.unattributedPlayDelta ?? 0
        if lhsUnattributed != rhsUnattributed {
            return lhsUnattributed < rhsUnattributed
        }

        if lhs.playedSongCount != rhs.playedSongCount {
            return lhs.playedSongCount > rhs.playedSongCount
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
        let monthInterval = calendar.recapMonthInterval(containing: capturedAt)
        return AggregateCounters(
            playCount: songs.reduce(0) { $0 + $1.playCount },
            skipCount: songs.reduce(0) { $0 + $1.skipCount },
            listeningDuration: songs.reduce(0) { $0 + (TimeInterval($1.playCount) * $1.playbackDuration) },
            monthNewSongCount: songs.filter {
                guard let dateAdded = $0.dateAdded else { return false }
                return monthInterval.contains(dateAdded)
            }.count
        )
    }

    private static func aggregateCounters(
        from songs: [SongSnapshot],
        capturedAt: Date,
        calendar: Calendar
    ) -> AggregateCounters {
        let monthInterval = calendar.recapMonthInterval(containing: capturedAt)
        return AggregateCounters(
            playCount: songs.reduce(0) { $0 + $1.playCount },
            skipCount: songs.reduce(0) { $0 + $1.skipCount },
            listeningDuration: songs.reduce(0) { $0 + (TimeInterval($1.playCount) * $1.playbackDuration) },
            monthNewSongCount: songs.filter {
                guard let dateAdded = $0.dateAdded else { return false }
                return monthInterval.contains(dateAdded)
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
                let monthInterval = calendar.recapMonthInterval(containing: baseline.capturedAt)
                let monthStart = monthInterval.start
                let monthEnd = monthInterval.end
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

        let ordered = canonical.sortedForSyncPayloads()
        var reliable: [LibrarySnapshot] = []
        for snapshot in ordered {
            let previous = reliable.last(where: { $0.isSameDevice(as: snapshot) })
            if let previous, isLikelyTransientCounterRegression(snapshot, after: previous) {
                continue
            }
            reliable.append(snapshot)
        }
        return reliable
    }

    private func recapCandidateForDeviceStream(
        for date: Date,
        snapshots ordered: [LibrarySnapshot],
        sourceSongs: [TopSong],
        sourceAlbums: [TopAlbum],
        sourceArtists: [TopArtist]
    ) -> RecapCandidate {
        let monthStart = calendar.startOfMonth(containing: date)
        let monthInterval = calendar.recapMonthInterval(containing: date)
        let calculationMonthStart = monthInterval.start
        let monthEnd = monthInterval.end

        guard let latest = ordered.last(where: { $0.capturedAt < monthEnd }) else {
            return RecapCandidate(
                recap: .empty(for: date, calendar: calendar),
                rankingCoverage: 0,
                sourceSnapshotCount: 0
            )
        }

        let inMonth = ordered.filter { monthInterval.contains($0.capturedAt) }
        let baseline = baselineSnapshot(
            for: latest,
            inMonth: inMonth,
            ordered: ordered,
            monthStart: calculationMonthStart
        )
        let artworkLookup = ArtworkLookup(sourceSongs: sourceSongs, sourceAlbums: sourceAlbums, sourceArtists: sourceArtists)
        let epochAnalysis = counterEpochAnalysis(
            baseline: baseline,
            inMonth: inMonth,
            latest: latest,
            history: ordered,
            monthStart: calculationMonthStart,
            monthEnd: monthEnd
        )
        let aggregateDeltas = aggregateDeltas(
            latest: latest,
            baseline: baseline,
            counterEpochAnalysis: epochAnalysis
        )
        let deltas = epochAnalysis.deltas

        let playDeltas = rankingDeltas(
            from: deltas.filter { $0.playDelta > 0 },
            monthStart: calculationMonthStart,
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
            subtitle: { $0.latest.albumArtist },
            artwork: { artworkLookup.albumArtwork(for: $0.latest) }
        )

        let biggestGainers = movementSongs(
            from: playDeltas,
            baseline: baseline,
            latest: latest,
            artworkLookup: artworkLookup
        )
        let biggestAlbumGainers = movementGroups(
            from: playDeltas,
            baseline: baseline,
            latest: latest,
            id: albumGroupID,
            snapshotID: albumGroupID,
            title: { $0.latest.albumTitle },
            subtitle: { $0.latest.albumArtist },
            artwork: { artworkLookup.albumArtwork(for: $0.latest) }
        )
        let biggestArtistGainers = movementGroups(
            from: playDeltas,
            baseline: baseline,
            latest: latest,
            id: artistGroupID,
            snapshotID: artistGroupID,
            title: { $0.latest.artist },
            subtitle: { _ in "Artist" },
            artwork: { artworkLookup.artistArtwork(for: $0.latest) }
        )

        let topNewSongs = playDeltas
            .filter(\.isNewSong)
            .sorted(by: compareDeltas)
            .map { rankedSong(from: $0, artworkLookup: artworkLookup) }

        let newSongCount = latest.songs.filter { song in
            guard let dateAdded = song.dateAdded else { return false }
            return dateAdded >= calculationMonthStart && dateAdded < monthEnd
        }.count
        let totalListeningDuration = aggregateDeltas?.listeningDuration ?? deltas.reduce(0) { $0 + $1.listeningDuration }
        let songLevelPlayDelta = playDeltas.reduce(0) { $0 + $1.playDelta }
        let expectedPlayDelta = aggregateDeltas?.playDelta ?? songLevelPlayDelta
        let rankingCoverage = expectedPlayDelta > 0
            ? min(1, Double(songLevelPlayDelta) / Double(expectedPlayDelta))
            : 1

        guard isPlausibleListeningDuration(
            totalListeningDuration,
            monthStart: calculationMonthStart,
            baseline: baseline,
            latest: latest
        ) else {
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
                trackingStart: baseline.capturedAt,
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
                biggestAlbumGainers: biggestAlbumGainers,
                biggestArtistGainers: biggestArtistGainers,
                topNewSongs: topNewSongs
            ),
            rankingCoverage: rankingCoverage,
            sourceSnapshotCount: inMonth.count
        )
    }

    private func counterEpochAnalysis(
        baseline: LibrarySnapshot,
        inMonth: [LibrarySnapshot],
        latest: LibrarySnapshot,
        history: [LibrarySnapshot],
        monthStart: Date,
        monthEnd: Date
    ) -> CounterEpochAnalysis {
        let eligibleInMonth = inMonth
            .filter {
                $0.isSameDevice(as: latest)
                    && hasComparableCoverage($0, latest: latest)
            }
            .sorted { $0.capturedAt < $1.capturedAt }
        let relevantHistory = history.filter {
            $0.capturedAt < monthEnd && $0.isSameDevice(as: latest)
        }
        let identityResolver = RecordingIdentityResolver(snapshots: relevantHistory)

        var epochs: [CounterEpoch] = []
        var activeEpochByPersistentID: [UInt64: Int] = [:]
        var recordingsKnownBeforeMonth = Set(
            relevantHistory
                .filter { $0.capturedAt < monthStart }
                .flatMap(\.songs)
                .map(identityResolver.identity(for:))
        )
        for song in baseline.songs
        where song.dateAdded.map({ $0 < monthStart }) ?? true {
            recordingsKnownBeforeMonth.insert(identityResolver.identity(for: song))
        }
        var knownRecordingIdentities = recordingsKnownBeforeMonth
        var previousSongsByID: [UInt64: SongSnapshot] = [:]
        var removedPlayCount = 0
        var removedSkipCount = 0
        var removedListeningDuration: TimeInterval = 0
        var confirmedDiscontinuityCount = 0

        for song in baseline.songs {
            let identity = identityResolver.identity(for: song)
            knownRecordingIdentities.insert(identity)
            activeEpochByPersistentID[song.id] = epochs.count
            epochs.append(
                CounterEpoch(
                    recordingIdentity: identity,
                    playbackStoreID: song.playbackStoreID,
                    baselinePlayCount: song.playCount,
                    baselineSkipCount: song.skipCount,
                    maximumPlayCount: song.playCount,
                    maximumSkipCount: song.skipCount,
                    latest: song
                )
            )
            previousSongsByID[song.id] = song
        }

        for snapshot in eligibleInMonth where snapshot.capturedAt > baseline.capturedAt {
            let currentSongsByID = Dictionary(uniqueKeysWithValues: snapshot.songs.map { ($0.id, $0) })
            var currentIdentityCounts: [String: Int] = [:]
            for song in snapshot.songs {
                currentIdentityCounts[identityResolver.identity(for: song), default: 0] += 1
            }

            for song in snapshot.songs {
                let identity = identityResolver.identity(for: song)

                if let activeIndex = activeEpochByPersistentID[song.id],
                   epochs[activeIndex].recordingIdentity == identity {
                    let epoch = epochs[activeIndex]
                    let dateAddedAdvanced = song.dateAdded.map { currentDateAdded in
                        guard currentDateAdded >= monthStart && currentDateAdded < monthEnd else {
                            return false
                        }
                        guard let priorDateAdded = epoch.latest.dateAdded else {
                            return true
                        }
                        return currentDateAdded.timeIntervalSince(priorDateAdded) > 60
                    } ?? false
                    let returnedAfterMissing = previousSongsByID[song.id] == nil
                    let substantialDrop = song.playCount <= max(10, epoch.maximumPlayCount / 4)
                    let isConfirmedReset = song.playCount < epoch.maximumPlayCount
                        && (dateAddedAdvanced || (returnedAfterMissing && substantialDrop))

                    if isConfirmedReset {
                        removedPlayCount += epoch.maximumPlayCount
                        removedSkipCount += epoch.maximumSkipCount
                        removedListeningDuration += TimeInterval(epoch.maximumPlayCount)
                            * epoch.latest.playbackDuration
                        confirmedDiscontinuityCount += 1

                        let shouldCountFromZero = song.dateAdded.map {
                            $0 >= monthStart && $0 < monthEnd
                        } ?? true
                        activeEpochByPersistentID[song.id] = epochs.count
                        epochs.append(
                            CounterEpoch(
                                recordingIdentity: identity,
                                playbackStoreID: song.playbackStoreID,
                                baselinePlayCount: shouldCountFromZero ? 0 : song.playCount,
                                baselineSkipCount: shouldCountFromZero ? 0 : song.skipCount,
                                maximumPlayCount: song.playCount,
                                maximumSkipCount: song.skipCount,
                                latest: song
                            )
                        )
                    } else {
                        epochs[activeIndex].maximumPlayCount = max(
                            epochs[activeIndex].maximumPlayCount,
                            song.playCount
                        )
                        epochs[activeIndex].maximumSkipCount = max(
                            epochs[activeIndex].maximumSkipCount,
                            song.skipCount
                        )
                        epochs[activeIndex].latest = song
                    }
                    continue
                }

                let isKnownRecording = knownRecordingIdentities.contains(identity)
                let wasAddedThisMonth = song.dateAdded.map {
                    $0 >= monthStart && $0 < monthEnd
                } ?? false
                let replacedMissingIdentity = isKnownRecording
                    && currentIdentityCounts[identity] == 1
                let shouldCountFromZero = wasAddedThisMonth || replacedMissingIdentity

                knownRecordingIdentities.insert(identity)
                activeEpochByPersistentID[song.id] = epochs.count
                epochs.append(
                    CounterEpoch(
                        recordingIdentity: identity,
                        playbackStoreID: song.playbackStoreID,
                        baselinePlayCount: shouldCountFromZero ? 0 : song.playCount,
                        baselineSkipCount: shouldCountFromZero ? 0 : song.skipCount,
                        maximumPlayCount: song.playCount,
                        maximumSkipCount: song.skipCount,
                        latest: song
                    )
                )
            }

            previousSongsByID = currentSongsByID
        }

        let latestSongIDs = Set(latest.songs.map(\.id))
        let removedActiveEpochs = activeEpochByPersistentID.compactMap { persistentID, epochIndex in
            latestSongIDs.contains(persistentID) ? nil : epochs[epochIndex]
        }
        confirmedDiscontinuityCount += removedActiveEpochs.count
        for epoch in removedActiveEpochs {
            removedPlayCount += epoch.maximumPlayCount
            removedSkipCount += epoch.maximumSkipCount
            removedListeningDuration += TimeInterval(epoch.maximumPlayCount)
                * epoch.latest.playbackDuration
        }

        let maximumReliableDiscontinuityCount = max(
            25,
            (latest.scannedSongCount ?? latest.songs.count) / 50
        )
        if confirmedDiscontinuityCount > maximumReliableDiscontinuityCount {
            removedPlayCount = 0
            removedSkipCount = 0
            removedListeningDuration = 0
        }

        var deltasByRecordingIdentity: [String: SongDelta] = [:]
        for epoch in epochs {
            let playDelta = max(0, epoch.maximumPlayCount - epoch.baselinePlayCount)
            let skipDelta = max(0, epoch.maximumSkipCount - epoch.baselineSkipCount)
            guard playDelta > 0 || skipDelta > 0 else { continue }

            let isNewSong = !recordingsKnownBeforeMonth.contains(epoch.recordingIdentity)
            if let existing = deltasByRecordingIdentity[epoch.recordingIdentity] {
                deltasByRecordingIdentity[epoch.recordingIdentity] = SongDelta(
                    latest: epoch.latest,
                    playDelta: existing.playDelta + playDelta,
                    skipDelta: existing.skipDelta + skipDelta,
                    recordingIdentity: epoch.recordingIdentity,
                    playbackStoreID: epoch.playbackStoreID ?? existing.playbackStoreID,
                    isNewSong: existing.isNewSong && isNewSong
                )
            } else {
                deltasByRecordingIdentity[epoch.recordingIdentity] = SongDelta(
                    latest: epoch.latest,
                    playDelta: playDelta,
                    skipDelta: skipDelta,
                    recordingIdentity: epoch.recordingIdentity,
                    playbackStoreID: epoch.playbackStoreID,
                    isNewSong: isNewSong
                )
            }
        }

        return CounterEpochAnalysis(
            deltas: Array(deltasByRecordingIdentity.values),
            removedPlayCount: removedPlayCount,
            removedSkipCount: removedSkipCount,
            removedListeningDuration: removedListeningDuration
        )
    }

    private func aggregateDeltas(
        latest: LibrarySnapshot,
        baseline: LibrarySnapshot,
        counterEpochAnalysis: CounterEpochAnalysis
    ) -> (playDelta: Int, skipDelta: Int, listeningDuration: TimeInterval)? {
        guard latest.isSameDevice(as: baseline),
              hasComparableCoverage(baseline, latest: latest),
              let latestCounters = latest.aggregateCounters,
              let baselineCounters = baseline.aggregateCounters else {
            return nil
        }

        return (
            playDelta: max(
                0,
                latestCounters.playCount - baselineCounters.playCount
                    + counterEpochAnalysis.removedPlayCount
            ),
            skipDelta: max(
                0,
                latestCounters.skipCount - baselineCounters.skipCount
                    + counterEpochAnalysis.removedSkipCount
            ),
            listeningDuration: max(
                0,
                latestCounters.listeningDuration - baselineCounters.listeningDuration
                    + counterEpochAnalysis.removedListeningDuration
            )
        )
    }

    private func rankingDeltas(
        from deltas: [SongDelta],
        monthStart: Date,
        monthEnd: Date,
        aggregatePlayDelta: Int?
    ) -> [SongDelta] {
        guard let aggregatePlayDelta, aggregatePlayDelta > 0 else {
            return deltas
        }

        let existingSongPlayDelta = deltas.reduce(0) { total, delta in
            delta.isNewSong ? total : total + delta.playDelta
        }
        guard existingSongPlayDelta > aggregatePlayDelta * 2 else {
            return deltas
        }

        return deltas.filter { delta in
            guard delta.isNewSong,
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
            artwork: artworkLookup.artwork(for: delta.latest),
            recordingIdentity: delta.recordingIdentity,
            playbackStoreID: delta.playbackStoreID
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
        }), !isUnobservedMonthGap(from: beforeMonth.capturedAt, to: latest.capturedAt) {
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
        guard hasComparableScanCount(baseline, latest: latest) else {
            return false
        }

        // Cloud payloads intentionally retain only priority songs, so their
        // aggregate scan counts are the available coverage signal. Local scans
        // contain every observed song and can additionally prove membership.
        guard baseline.songs.count >= baselineCount,
              latest.songs.count >= latestCount else {
            return true
        }

        let resolver = RecordingIdentityResolver(snapshots: [baseline, latest])
        let baselineIdentities = Set(baseline.songs.map { resolver.identity(for: $0) })
        let latestSongsByIdentity = Dictionary(
            grouping: latest.songs,
            by: { resolver.identity(for: $0) }
        )
        let latestIdentities = Set(latestSongsByIdentity.keys)
        guard baselineIdentities.isSubset(of: latestIdentities) else {
            return false
        }

        let addedIdentities = latestIdentities.subtracting(baselineIdentities)
        return addedIdentities.allSatisfy { identity in
            latestSongsByIdentity[identity]?.allSatisfy { song in
                song.dateAdded.map { $0 >= baseline.capturedAt } ?? false
            } ?? false
        }
    }

    private func hasComparableScanCount(_ baseline: LibrarySnapshot, latest: LibrarySnapshot) -> Bool {
        let baselineCount = baseline.scannedSongCount ?? baseline.songs.count
        let latestCount = latest.scannedSongCount ?? latest.songs.count
        guard baselineCount > 0, latestCount > 0 else {
            return baselineCount == latestCount
        }
        return Double(min(baselineCount, latestCount)) / Double(max(baselineCount, latestCount))
            >= minimumComparableCoverageRatio
    }

    /// A single incomplete MediaPlayer query must never become a counter
    /// baseline. A real large library edit is promoted only after a library
    /// shape and a later observation confirms it. Promotion rebases without
    /// counting the coverage difference as plays.
    private func confirmsStableCoverageChange(
        _ snapshot: LibrarySnapshot,
        in stored: StoredSnapshots
    ) -> Bool {
        let latestCount = snapshot.scannedSongCount ?? snapshot.songs.count
        guard let pending = stored.reliabilityEvents.reversed().first(where: {
            $0.kind == .rejectedCoverageDrop &&
                $0.occurredAt > (stored.lastTrustedObservationAt ?? .distantPast)
        }) else {
            return false
        }

        guard snapshot.capturedAt.timeIntervalSince(pending.occurredAt) >= minimumSnapshotInterval,
              snapshot.capturedAt.timeIntervalSince(pending.occurredAt) <= 7 * 24 * 60 * 60 else {
            return false
        }

        let pendingCount = pending.scannedSongCount
        guard pending.coverageSignature == snapshot.coverageSignature else {
            return false
        }
        guard pendingCount > 0, latestCount > 0 else {
            return pendingCount == latestCount
        }
        return Double(min(pendingCount, latestCount)) / Double(max(pendingCount, latestCount))
            >= minimumComparableCoverageRatio
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

    private func artistGroupID(for delta: SongDelta) -> String {
        artistGroupID(for: delta.latest)
    }

    private func artistGroupID(for song: SongSnapshot) -> String {
        if song.artistPersistentID != 0 {
            return String(song.artistPersistentID)
        }

        return "artist:\(normalizedGroupKey(song.artist))"
    }

    private func albumGroupID(for delta: SongDelta) -> String {
        albumGroupID(for: delta.latest)
    }

    private func albumGroupID(for song: SongSnapshot) -> String {
        if song.albumPersistentID != 0 {
            return String(song.albumPersistentID)
        }

        return [
            "album",
            normalizedGroupKey(song.albumTitle),
            normalizedGroupKey(song.albumArtist)
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

    private func movementGroups(
        from deltas: [SongDelta],
        baseline: LibrarySnapshot,
        latest: LibrarySnapshot,
        id: (SongDelta) -> String,
        snapshotID: (SongSnapshot) -> String,
        title: (SongDelta) -> String,
        subtitle: (SongDelta) -> String,
        artwork: (SongDelta) -> MPMediaItemArtwork?
    ) -> [MonthlyRecap.MovementGroup] {
        let baselineRanks = groupRanksByPlayCount(for: baseline.songs, id: snapshotID)
        let latestRanks = groupRanksByPlayCount(for: latest.songs, id: snapshotID)
        var aggregates: [String: (title: String, subtitle: String, playDelta: Int, artwork: MPMediaItemArtwork?)] = [:]
        for delta in deltas {
            let groupID = id(delta)
            let existing = aggregates[groupID]
            aggregates[groupID] = (existing?.title ?? title(delta), existing?.subtitle ?? subtitle(delta),
                                   (existing?.playDelta ?? 0) + delta.playDelta, existing?.artwork ?? artwork(delta))
        }
        return aggregates.compactMap { groupID, value in
            guard let previousRank = baselineRanks[groupID], let currentRank = latestRanks[groupID], previousRank > currentRank else { return nil }
            return MonthlyRecap.MovementGroup(id: groupID, title: value.title, subtitle: value.subtitle,
                                              playDelta: value.playDelta, rankChange: previousRank - currentRank,
                                              currentRank: currentRank, previousRank: previousRank, artwork: value.artwork)
        }.sorted {
            $0.rankChange == $1.rankChange ? ($0.playDelta == $1.playDelta ? $0.title < $1.title : $0.playDelta > $1.playDelta) : $0.rankChange > $1.rankChange
        }
    }

    private func groupRanksByPlayCount(for songs: [SongSnapshot], id: (SongSnapshot) -> String) -> [String: Int] {
        var totals: [String: Int] = [:]
        for song in songs { totals[id(song), default: 0] += song.playCount }
        let ranked = totals.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        return Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($0.element.key, $0.offset + 1) })
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

    /// Upgrades ledgers written before missed-month intervals were modeled.
    /// Only month boundaries with at least one fully skipped calendar month are
    /// inspected, and only their destination month/year summaries are replaced.
    private func migrateGapPolicyIfNeeded(in stored: inout StoredSnapshots) -> Bool {
        guard stored.gapPolicyVersion < Self.currentGapPolicyVersion else { return false }
        stored.gapPolicyVersion = Self.currentGapPolicyVersion

        let streams = Dictionary(grouping: stored.snapshots.sortedForSyncPayloads()) {
            $0.logicalDeviceKey(fallbackDeviceIdentifier: deviceIdentifier)
        }
        var discoveredIntervals: [UnattributedRecapInterval] = []
        var affectedMonths: Set<Date> = []

        for stream in streams.values {
            let ordered = canonicalSnapshots(stream)
            guard ordered.count > 1 else { continue }
            for index in 1..<ordered.count {
                let previous = ordered[index - 1]
                let current = ordered[index]
                guard isUnobservedMonthGap(from: previous.capturedAt, to: current.capturedAt) else {
                    continue
                }
                affectedMonths.insert(calendar.startOfMonth(containing: current.capturedAt))
                if let interval = unattributedInterval(
                    from: previous,
                    to: current,
                    history: ordered
                ) {
                    discoveredIntervals.append(interval)
                }
            }
        }

        guard !affectedMonths.isEmpty else { return true }
        if stored.monthlyLedgers.isEmpty {
            stored.monthlyLedgers = stored.syncedRecaps
        }
        stored.unattributedIntervals = durableUnattributedIntervals(
            Self.mergedUnattributedIntervals(stored.unattributedIntervals + discoveredIntervals)
        )

        for monthStart in affectedMonths {
            let rebuilt = SyncedMonthlyRecap(
                recap: snapshotRecap(for: monthStart, snapshots: stored.snapshots),
                preservingAllRankings: true
            )
            let existing = stored.monthlyLedgers.first { $0.monthStart == monthStart }
            if let existing, existing.snapshotCount > rebuilt.snapshotCount {
                continue
            }
            stored.monthlyLedgers.removeAll { $0.monthStart == monthStart }
            stored.monthlyLedgers.append(rebuilt)
            stored.syncedRecaps.removeAll { $0.monthStart == monthStart }
            stored.syncedRecaps.append(rebuilt.compacted())
        }
        stored.monthlyLedgers.sort { $0.monthStart < $1.monthStart }
        stored.syncedRecaps.sort { $0.monthStart < $1.monthStart }

        let affectedYears = Set(affectedMonths.map { calendar.recapYear(containing: $0) })
        let rebuiltYears = yearlyRecaps(
            from: stored.monthlyLedgers,
            unattributedIntervals: stored.unattributedIntervals
        ).filter { affectedYears.contains($0.year) }
        stored.syncedYearlyRecaps.removeAll { affectedYears.contains($0.year) }
        stored.syncedYearlyRecaps.append(contentsOf: rebuiltYears)
        stored.syncedYearlyRecaps.sort { $0.year < $1.year }
        return true
    }

    /// Backfills the exact artist total into compact recap summaries written before
    /// that aggregate existed. Full monthly ledgers retain every ranked artist, so
    /// they can upgrade old months and rebuild exact yearly unions without rescanning
    /// the snapshot archive.
    private func migrateListenedArtistCountsIfNeeded(in stored: inout StoredSnapshots) -> Bool {
        let hasMissingCounts = stored.monthlyLedgers.contains { $0.listenedArtistCount == nil } ||
            stored.syncedRecaps.contains { $0.listenedArtistCount == nil } ||
            stored.syncedYearlyRecaps.contains { $0.recap.listenedArtistCount == nil }
        guard hasMissingCounts else { return false }

        let artworkLookup = ArtworkLookup(sourceSongs: [])
        stored.monthlyLedgers = stored.monthlyLedgers.map {
            SyncedMonthlyRecap(
                recap: $0.monthlyRecap(artworkLookup: artworkLookup),
                preservingAllRankings: true,
                reliabilityPolicyVersion: $0.reliabilityPolicyVersion
            )
        }
        stored.syncedRecaps = stored.syncedRecaps.map {
            SyncedMonthlyRecap(
                recap: $0.monthlyRecap(artworkLookup: artworkLookup),
                reliabilityPolicyVersion: $0.reliabilityPolicyVersion
            )
        }
        stored.syncedYearlyRecaps = stored.syncedYearlyRecaps.map {
            SyncedYearlyRecap(
                year: $0.year,
                recap: $0.monthlyRecap(artworkLookup: artworkLookup),
                reliabilityPolicyVersion: $0.recap.reliabilityPolicyVersion
            )
        }

        if !stored.monthlyLedgers.isEmpty {
            let rebuilt = yearlyRecaps(
                from: stored.monthlyLedgers,
                unattributedIntervals: stored.unattributedIntervals
            )
            let rebuiltYears = Set(rebuilt.map(\.year))
            stored.syncedYearlyRecaps.removeAll { rebuiltYears.contains($0.year) }
            stored.syncedYearlyRecaps.append(contentsOf: rebuilt)
            stored.syncedYearlyRecaps.sort { $0.year < $1.year }
        }
        return true
    }

    /// Canonicalizes legacy local-midnight month identities before repairing the
    /// final evidence-backed month in each device stream. This prevents the same
    /// logical month from being summed more than once after travel or time-zone
    /// changes while retaining historical ledgers that lack comparable evidence.
    private func migrateCounterReliabilityPolicyIfNeeded(in stored: inout StoredSnapshots) -> Bool {
        guard stored.counterReliabilityPolicyVersion < Self.currentCounterReliabilityPolicyVersion else {
            return false
        }
        stored.counterReliabilityPolicyVersion = Self.currentCounterReliabilityPolicyVersion

        if stored.monthlyLedgers.isEmpty {
            stored.monthlyLedgers = stored.syncedRecaps
        }

        let legacyLedgerCount = stored.monthlyLedgers.count
        stored.monthlyLedgers = Self.mergedSyncedRecaps(stored.monthlyLedgers).map {
            Self.normalizedSyncedRecap(
                $0,
                monthStart: Self.canonicalPersistedMonthStart($0.monthStart),
                reliabilityPolicyVersion: $0.reliabilityPolicyVersion,
                preservingAllRankings: true
            )
        }
        let normalizedSummaryOnlyRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps).map {
            Self.normalizedSyncedRecap(
                $0,
                monthStart: Self.canonicalPersistedMonthStart($0.monthStart),
                reliabilityPolicyVersion: $0.reliabilityPolicyVersion,
                preservingAllRankings: false
            )
        }
        stored.syncedRecaps = Self.mergedSyncedRecaps(
            normalizedSummaryOnlyRecaps + stored.monthlyLedgers.map { $0.compacted() }
        )
        let collapsedLedgerCount = max(0, legacyLedgerCount - stored.monthlyLedgers.count)
        if collapsedLedgerCount > 0 {
            print("Recap month identity migration collapsed \(collapsedLedgerCount) duplicate month ledger(s)")
        }

        // Repair every stream's final month only when a comparable observation
        // survives. A stale device's lone historical baseline is not evidence and
        // must never replace a durable recap.
        let streams = recapCandidateStreams(from: stored.snapshots.sortedForSyncPayloads())
        let repairableFinalMonthByStream = streams.map { stream -> (source: Date, persisted: Date)? in
            let ordered = canonicalSnapshots(stream)
            guard let latest = ordered.last else { return nil }
            let monthInterval = calendar.recapMonthInterval(containing: latest.capturedAt)
            let inMonthCount = ordered.filter { monthInterval.contains($0.capturedAt) }.count
            let hasPriorBaseline = ordered.contains { $0.capturedAt < monthInterval.start }
            guard inMonthCount >= 2 || hasPriorBaseline else { return nil }
            let sourceMonthStart = calendar.startOfMonth(containing: latest.capturedAt)
            let candidate = recapCandidateForDeviceStream(
                for: sourceMonthStart,
                snapshots: stream,
                sourceSongs: [],
                sourceAlbums: [],
                sourceArtists: []
            ).recap
            // Historical capture timestamps are absolute instants, but the month
            // they represented was defined in the timezone active when saved.
            // Only an existing durable ledger can supply that persisted identity.
            // Without this match, travel could reinterpret an August capture as
            // July and append a duplicate rather than repairing August in place.
            guard let persistedMonthStart = stored.monthlyLedgers.first(where: {
                abs($0.generatedAt.timeIntervalSince(candidate.generatedAt)) < 0.001
            })?.monthStart,
                  persistedMonthStart == sourceMonthStart else {
                // The evidence was grouped under another timezone when saved.
                // Its original local boundary is unknowable in this legacy
                // schema, so preserving the durable ledger is safer than a
                // speculative repair or an adjacent-month duplicate.
                return nil
            }
            return (sourceMonthStart, persistedMonthStart)
        }
        let repairableMonthStarts = Set(repairableFinalMonthByStream.compactMap { $0?.persisted })

        for monthStart in repairableMonthStarts.sorted() {
            let rankedCandidates = streams.enumerated().compactMap { index, stream -> RecapCandidate? in
                guard let repair = repairableFinalMonthByStream[index],
                      repair.persisted == monthStart else {
                    return nil
                }
                return recapCandidateForDeviceStream(
                    for: repair.source,
                    snapshots: stream,
                    sourceSongs: [],
                    sourceAlbums: [],
                    sourceArtists: []
                )
            }.sorted { isHigherPriorityCandidate($0, than: $1) }
            guard let winner = rankedCandidates.first else {
                continue
            }
            let rebuiltRecap = winner.recap
            let existing = stored.monthlyLedgers.first { $0.monthStart == monthStart }
            let wouldErasePopulatedHistory = (existing?.totalPlayDelta ?? 0) > 0 && rebuiltRecap.totalPlayDelta == 0
            let wouldDegradeExistingEvidence = existing.map { existing in
                let existingRecap = existing.monthlyRecap(artworkLookup: ArtworkLookup(sourceSongs: []))
                let matchingWinnerEvidence = abs(
                    existingRecap.generatedAt.timeIntervalSince(rebuiltRecap.generatedAt)
                ) < 0.001 && hasMatchingRankingEvidence(existingRecap, rebuiltRecap)
                return (rebuiltRecap.totalPlayDelta < existingRecap.totalPlayDelta && !matchingWinnerEvidence) ||
                    (rebuiltRecap.totalPlayDelta == existingRecap.totalPlayDelta &&
                        isHigherPriorityDisplayRecap(existingRecap, than: rebuiltRecap))
            } ?? false
            if rebuiltRecap.snapshotCount > 0 && !wouldErasePopulatedHistory && !wouldDegradeExistingEvidence {
                let full = Self.normalizedSyncedRecap(
                    SyncedMonthlyRecap(recap: rebuiltRecap, preservingAllRankings: true),
                    monthStart: monthStart,
                    reliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion,
                    preservingAllRankings: true
                )
                stored.monthlyLedgers.removeAll { $0.monthStart == monthStart }
                stored.monthlyLedgers.append(full)
                stored.syncedRecaps.removeAll { $0.monthStart == monthStart }
                stored.syncedRecaps.append(full.compacted())
            }
        }

        stored.monthlyLedgers.sort { $0.monthStart < $1.monthStart }
        stored.syncedRecaps.sort { $0.monthStart < $1.monthStart }
        let allMonthlyEvidence = Self.mergedSyncedRecaps(stored.monthlyLedgers + stored.syncedRecaps)
        let affectedYears = Set(allMonthlyEvidence.map { calendar.recapYear(containing: $0.monthStart) })
        let rebuiltYears = yearlyRecaps(
            from: allMonthlyEvidence,
            unattributedIntervals: stored.unattributedIntervals
        ).filter { affectedYears.contains($0.year) }
        stored.syncedYearlyRecaps.removeAll { affectedYears.contains($0.year) }
        stored.syncedYearlyRecaps.append(contentsOf: rebuiltYears)
        stored.syncedYearlyRecaps.sort { $0.year < $1.year }
        print("Recap reliability policy migration finished at version \(Self.currentCounterReliabilityPolicyVersion)")
        return true
    }

    private func hasMatchingRankingEvidence(_ lhs: MonthlyRecap, _ rhs: MonthlyRecap) -> Bool {
        let lhsSongs = Set(lhs.topSongs.map { $0.recordingIdentity ?? "id:\($0.id)" })
        let rhsSongs = Set(rhs.topSongs.map { $0.recordingIdentity ?? "id:\($0.id)" })
        guard !lhsSongs.isEmpty, !rhsSongs.isEmpty else { return false }
        return !lhsSongs.isDisjoint(with: rhsSongs)
    }

    private func loadLocked() -> StoredSnapshots {
        if let loadedSnapshots, !ledgerLoadRetryPending, !legacyArchiveReadRetryPending {
            return loadedSnapshots
        }

        let ledger = LedgerDatabase(url: ledgerURL)
        do {
            guard persistenceReadAllowed() else {
                throw CocoaError(.fileReadUnknown)
            }
            if var stored = try ledger.load() {
                ledgerReadUnavailable = false
                ledgerLoadRetryPending = false
                persistenceSavePending = false
                var didMigrate = migrateGapPolicyIfNeeded(in: &stored)
                if migrateCounterReliabilityPolicyIfNeeded(in: &stored) {
                    didMigrate = true
                }
                if migrateListenedArtistCountsIfNeeded(in: &stored) {
                    didMigrate = true
                }
                if didMigrate {
                    do {
                        guard persistenceWriteAllowed() else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        try ledger.save(stored)
                        try writeSummaryCache(for: stored)
                    } catch {
                        // The full ledger was read successfully. Retain this state
                        // and retry on a later capture instead of degrading to a
                        // summary-only cache or requiring an app relaunch.
                        persistenceSavePending = true
                        loadedSnapshots = stored
                        #if DEBUG
                        print("Recap ledger migration save deferred: \(error)")
                        #endif
                        return stored
                    }
                } else if !isPrimarySummaryCacheCurrent(for: stored) {
                    // The ledger is authoritative and healthy. Repair a missing
                    // or corrupt presentation cache so a later UI read does not
                    // remain empty for the rest of the session.
                    do {
                        try writeSummaryCache(for: stored)
                    } catch {
                        persistenceSavePending = true
                        #if DEBUG
                        print("Recap summary cache repair deferred: \(error)")
                        #endif
                    }
                }
                if !FileManager.default.fileExists(atPath: ledgerAuthorityMarkerURL.path),
                   !FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        // Backfill the marker for healthy SQLite-only installs so
                        // later file loss cannot silently create writable empty
                        // history while durable summaries still survive.
                        try markLedgerAuthoritative()
                    } catch {
                        persistenceSavePending = true
                        #if DEBUG
                        print("Recap ledger authority marker backfill deferred: \(error)")
                        #endif
                    }
                }
                if FileManager.default.fileExists(atPath: ledgerAuthorityMarkerURL.path),
                   FileManager.default.fileExists(atPath: fileURL.path) {
                    do {
                        let retired = try retireLegacyArchiveIfPresent()
                        if let retired { try? FileManager.default.removeItem(at: retired) }
                    } catch {
                        #if DEBUG
                        print("Recap stale legacy archive cleanup deferred: \(error)")
                        #endif
                    }
                }
                loadedSnapshots = stored
                return stored
            }
        } catch {
            if ledger.exists {
                if FileManager.default.fileExists(atPath: fileURL.path),
                   !FileManager.default.fileExists(atPath: ledgerAuthorityMarkerURL.path) {
                    // The JSON archive remains authoritative until conversion is
                    // verified and the archive is removed. Fall through and retry
                    // it even if an earlier attempt created a partial SQLite file.
                    ledgerReadUnavailable = false
                    ledgerLoadRetryPending = false
                    persistenceSavePending = true
                } else {
                    let fallback = summaryCacheFallback()
                    if LedgerDatabase.isDefinitiveCorruption(error) {
                        ledgerReadUnavailable = true
                        ledgerLoadRetryPending = false
                    } else {
                        // Busy, I/O, protection, and other transient failures are
                        // retried. Summary-only state is never allowed to overwrite
                        // the authoritative ledger while that retry is pending.
                        ledgerLoadRetryPending = true
                        persistenceSavePending = true
                    }
                    loadedSnapshots = fallback
                    #if DEBUG
                    print("Recap ledger load failed; using protected summary cache: \(error)")
                    #endif
                    return fallback
                }
            }
        }

        if FileManager.default.fileExists(atPath: ledgerAuthorityMarkerURL.path), !ledger.exists {
            // A verified ledger once superseded the JSON. A partial restore or
            // file loss must never make that stale source authoritative again.
            ledgerReadUnavailable = true
            ledgerLoadRetryPending = false
            persistenceSavePending = true
            let fallback = summaryCacheFallback()
            loadedSnapshots = fallback
            return fallback
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = StoredSnapshots(
                schemaVersion: 3,
                counterReliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion,
                snapshots: []
            )
            loadedSnapshots = empty
            return empty
        }

        do {
            guard legacyArchiveReadAllowed() else {
                throw CocoaError(.fileReadUnknown)
            }
            let legacy = try streamedLegacyArchive()
            legacyArchiveReadRetryPending = false

            do {
                guard persistenceWriteAllowed() else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let quarantinedLedgerURLs = try quarantineIncompleteLedgerForLegacyRetry()
                quarantinedLedgerURLsPendingCleanup.append(contentsOf: quarantinedLedgerURLs)
                try ledger.save(legacy)
                guard let verified = try ledger.load(),
                      verified.snapshots.map(\.syncIdentifier) == legacy.snapshots.map(\.syncIdentifier),
                      verified.monthlyLedgers == legacy.monthlyLedgers,
                      verified.syncedRecaps == legacy.syncedRecaps,
                      verified.syncedYearlyRecaps == legacy.syncedYearlyRecaps,
                      verified.unattributedIntervals == legacy.unattributedIntervals else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                try writeSummaryCache(for: verified)
                try markLedgerAuthoritative()
                let retiredLegacyArchive = try retireLegacyArchiveIfPresent()
                cleanUpQuarantinedLedgerFiles()
                if let retiredLegacyArchive {
                    try? FileManager.default.removeItem(at: retiredLegacyArchive)
                }
                ledgerReadUnavailable = false
                ledgerLoadRetryPending = false
                persistenceSavePending = false
                loadedSnapshots = verified
                return verified
            } catch {
                // Migration is intentionally fail-open: the verified legacy
                // archive remains authoritative until a later attempt succeeds.
                persistenceSavePending = true
                loadedSnapshots = legacy
                return legacy
            }
        } catch {
            // The legacy archive is still authoritative. A protection or I/O
            // failure must never be converted into a new writable empty ledger.
            legacyArchiveReadRetryPending = true
            persistenceSavePending = true
            let fallback = summaryCacheFallback()
            loadedSnapshots = fallback
            #if DEBUG
            print("Recap legacy archive read deferred; using protected summary cache: \(error)")
            #endif
            return fallback
        }
    }

    private func quarantineIncompleteLedgerForLegacyRetry() throws -> [URL] {
        let suffix = ".incomplete-\(UUID().uuidString)"
        var quarantined: [URL] = []
        // Move the main database last. If moving a sidecar fails, the next retry
        // still sees the database and remains on the legacy-authoritative path.
        for source in [
            URL(fileURLWithPath: ledgerURL.path + "-wal"),
            URL(fileURLWithPath: ledgerURL.path + "-shm"),
            ledgerURL
        ] where FileManager.default.fileExists(atPath: source.path) {
            let destination = URL(fileURLWithPath: source.path + suffix)
            try FileManager.default.moveItem(
                at: source,
                to: destination
            )
            quarantined.append(destination)
        }
        return quarantined
    }

    private func retireLegacyArchiveIfPresent() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard legacyArchiveRetirementAllowed() else {
            throw CocoaError(.fileWriteUnknown)
        }
        let retiredURL = fileURL.appendingPathExtension("migrated-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: fileURL, to: retiredURL)
        return retiredURL
    }

    private func cleanUpQuarantinedLedgerFiles() {
        quarantinedLedgerURLsPendingCleanup.forEach { try? FileManager.default.removeItem(at: $0) }
        quarantinedLedgerURLsPendingCleanup.removeAll()
    }

    /// Reads the old JSON archive one snapshot at a time. A real archive can be
    /// hundreds of megabytes; decoding the top-level object would temporarily
    /// retain every library scan and exceed iOS's foreground memory budget.
    private func streamedLegacyArchive() throws -> StoredSnapshots {
        var stored = StoredSnapshots(schemaVersion: 3, snapshots: [])

        try forEachLegacySnapshot { decodedSnapshot in
            let snapshot: LibrarySnapshot
            if decodedSnapshot.aggregateCounters == nil {
                snapshot = LibrarySnapshot(
                    capturedAt: decodedSnapshot.capturedAt,
                    reason: decodedSnapshot.reason,
                    appVersion: decodedSnapshot.appVersion,
                    scannedSongCount: decodedSnapshot.scannedSongCount,
                    deviceIdentifier: decodedSnapshot.deviceIdentifier,
                    aggregateCounters: Self.aggregateCounters(
                        from: decodedSnapshot.songs,
                        capturedAt: decodedSnapshot.capturedAt,
                        calendar: calendar
                    ),
                    songs: decodedSnapshot.songs
                )
            } else {
                snapshot = decodedSnapshot
            }

            guard shouldAppend(snapshot, after: stored.snapshots.last) else { return }
            let previous = stored.snapshots.last(where: {
                $0.capturedAt < snapshot.capturedAt && $0.isSameDevice(as: snapshot)
            })
            stored.snapshots.append(snapshot)
            stored.snapshots = retainedCanonicalSnapshots(
                from: stored.snapshots,
                now: snapshot.capturedAt
            )
            if let previous, isUnobservedMonthGap(from: previous.capturedAt, to: snapshot.capturedAt) {
                if let interval = unattributedInterval(
                    from: previous,
                    to: snapshot,
                    history: stored.snapshots
                ) {
                    stored.unattributedIntervals = Self.mergedUnattributedIntervals(
                        stored.unattributedIntervals + [interval]
                    )
                }
                establishMonthlyBaseline(in: &stored, current: snapshot, rebuildYearly: false)
            } else {
                updateIncrementalRecap(in: &stored, previous: previous, current: snapshot, rebuildYearly: false)
            }
            stored.snapshots = compactSnapshotsForLocalStorage(from: stored.snapshots)
        }

        stored.syncedYearlyRecaps = yearlyRecaps(
            from: stored.monthlyLedgers,
            unattributedIntervals: stored.unattributedIntervals
        )

        // Raw snapshots may already have aged out of the legacy JSON. Preserve
        // its compact top-level ledgers directly, then merge any validated cache
        // copy. The array extractor streams the file instead of loading a large
        // historical archive into memory.
        let legacyArrays = try streamedLegacyTopLevelArrays(keys: [
            "monthlyLedgers",
            "syncedRecaps",
            "syncedYearlyRecaps",
            "unattributedIntervals"
        ])
        func decodePresentArray<Element: Decodable>(_ key: String, as: Element.Type) throws -> [Element] {
            guard let data = legacyArrays[key] else { return [] }
            return try JSONDecoder.playCount.decode([Element].self, from: data)
        }
        let legacyMonthlyLedgers = try decodePresentArray("monthlyLedgers", as: SyncedMonthlyRecap.self)
        let legacySyncedRecaps = try decodePresentArray("syncedRecaps", as: SyncedMonthlyRecap.self)
        let legacyYearlyRecaps = try decodePresentArray("syncedYearlyRecaps", as: SyncedYearlyRecap.self)
        let legacyIntervals = try decodePresentArray("unattributedIntervals", as: UnattributedRecapInterval.self)
        stored.monthlyLedgers = Self.mergedSyncedRecaps(stored.monthlyLedgers + legacyMonthlyLedgers)
        stored.syncedRecaps = Self.mergedSyncedRecaps(stored.syncedRecaps + legacySyncedRecaps + legacyMonthlyLedgers)
        stored.syncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(stored.syncedYearlyRecaps + legacyYearlyRecaps)
        stored.unattributedIntervals = Self.mergedUnattributedIntervals(stored.unattributedIntervals + legacyIntervals)

        // Preserve any higher-quality Cloud summary that was already cached.
        if let summaries = resolvedSummaryCache() {
            stored.monthlyLedgers = Self.mergedSyncedRecaps(
                stored.monthlyLedgers + summaries.monthlyRecaps
            )
            stored.syncedRecaps = Self.mergedSyncedRecaps(
                stored.syncedRecaps + summaries.monthlyRecaps
            )
            stored.syncedYearlyRecaps = Self.mergedSyncedYearlyRecaps(
                stored.syncedYearlyRecaps + summaries.yearlyRecaps
            )
        }
        return stored
    }

    private func streamedLegacyTopLevelArrays(keys: Set<String>) throws -> [String: Data] {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var results: [String: Data] = [:]
        var objectDepth = 0
        var arrayDepth = 0
        var inString = false
        var escaped = false
        var keyBuffer = Data()
        var pendingKey: String?
        var awaitingValueForKey: String?
        var captureKey: String?
        var captureData = Data()
        var captureArrayDepth = 0
        var captureInString = false
        var captureEscaped = false
        var encounteredTargetKeys = Set<String>()

        while let chunk = try handle.read(upToCount: 256 * 1_024), !chunk.isEmpty {
            for byte in chunk {
                if let activeKey = captureKey {
                    captureData.append(byte)
                    if captureInString {
                        if captureEscaped {
                            captureEscaped = false
                        } else if byte == 0x5C {
                            captureEscaped = true
                        } else if byte == 0x22 {
                            captureInString = false
                        }
                    } else if byte == 0x22 {
                        captureInString = true
                    } else if byte == 0x5B {
                        captureArrayDepth += 1
                    } else if byte == 0x5D {
                        captureArrayDepth -= 1
                        if captureArrayDepth == 0 {
                            results[activeKey] = captureData
                            captureKey = nil
                            captureData = Data()
                        }
                    }
                    continue
                }

                if inString {
                    if escaped {
                        escaped = false
                        if objectDepth == 1 && arrayDepth == 0 { keyBuffer.append(byte) }
                    } else if byte == 0x5C {
                        escaped = true
                        if objectDepth == 1 && arrayDepth == 0 { keyBuffer.append(byte) }
                    } else if byte == 0x22 {
                        inString = false
                        if objectDepth == 1 && arrayDepth == 0 {
                            pendingKey = String(data: keyBuffer, encoding: .utf8)
                        }
                        keyBuffer = Data()
                    } else if objectDepth == 1 && arrayDepth == 0 {
                        keyBuffer.append(byte)
                    }
                    continue
                }

                if let key = awaitingValueForKey, keys.contains(key),
                   ![0x20, 0x09, 0x0A, 0x0D].contains(byte), byte != 0x5B {
                    throw CocoaError(.fileReadCorruptFile)
                }

                if byte == 0x22 {
                    inString = true
                    keyBuffer = Data()
                } else if byte == 0x7B {
                    objectDepth += 1
                } else if byte == 0x7D {
                    objectDepth -= 1
                } else if byte == 0x5B {
                    if let key = awaitingValueForKey, keys.contains(key) {
                        captureKey = key
                        captureData = Data([byte])
                        captureArrayDepth = 1
                        captureInString = false
                        captureEscaped = false
                        awaitingValueForKey = nil
                    } else {
                        arrayDepth += 1
                    }
                } else if byte == 0x5D {
                    arrayDepth -= 1
                } else if byte == 0x3A, objectDepth == 1, arrayDepth == 0 {
                    awaitingValueForKey = pendingKey
                    if let pendingKey, keys.contains(pendingKey) {
                        encounteredTargetKeys.insert(pendingKey)
                    }
                    pendingKey = nil
                } else if ![0x20, 0x09, 0x0A, 0x0D].contains(byte),
                          let key = awaitingValueForKey {
                    awaitingValueForKey = nil
                    if keys.contains(key) {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                }
            }
            if Set(results.keys).isSuperset(of: keys) { break }
        }
        guard captureKey == nil else { throw CocoaError(.fileReadCorruptFile) }
        guard Set(results.keys).isSuperset(of: encounteredTargetKeys) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return results
    }

    private func forEachLegacySnapshot(
        _ body: (LibrarySnapshot) throws -> Void
    ) throws {
        if try forEachPrettyPrintedLegacySnapshot(body) {
            return
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        let key = Array("\"snapshots\"".utf8)
        var keyIndex = 0
        var foundKey = false
        var foundArray = false
        var object = Data()
        object.reserveCapacity(1_000_000)
        var depth = 0
        var inString = false
        var isEscaped = false

        while let chunk = try handle.read(upToCount: 256 * 1_024), !chunk.isEmpty {
            for byte in chunk {
                if !foundKey {
                    if byte == key[keyIndex] {
                        keyIndex += 1
                        if keyIndex == key.count {
                            foundKey = true
                        }
                    } else {
                        keyIndex = byte == key[0] ? 1 : 0
                    }
                    continue
                }

                if !foundArray {
                    if byte == Character("[").asciiValue {
                        foundArray = true
                    }
                    continue
                }

                if depth == 0 {
                    if byte == Character("]").asciiValue {
                        return
                    }
                    guard byte == Character("{").asciiValue || byte.isJSONWhitespaceOrComma else {
                        throw LegacyStreamError.malformedSnapshotArray
                    }
                    guard byte == Character("{").asciiValue else { continue }
                    object.removeAll(keepingCapacity: true)
                    object.append(byte)
                    depth = 1
                    inString = false
                    isEscaped = false
                    continue
                }

                object.append(byte)
                if inString {
                    if isEscaped {
                        isEscaped = false
                    } else if byte == Character("\\").asciiValue {
                        isEscaped = true
                    } else if byte == Character("\"").asciiValue {
                        inString = false
                    }
                    continue
                }

                if byte == Character("\"").asciiValue {
                    inString = true
                } else if byte == Character("{").asciiValue {
                    depth += 1
                } else if byte == Character("}").asciiValue {
                    depth -= 1
                    if depth == 0 {
                        try autoreleasepool {
                            try body(JSONDecoder.playCount.decode(LibrarySnapshot.self, from: object))
                        }
                    }
                }
            }
        }

        guard foundKey, foundArray else {
            throw LegacyStreamError.snapshotsArrayMissing
        }
        throw LegacyStreamError.truncatedSnapshot
    }

    /// Legacy archives were written with `.prettyPrinted`. Memory-mapping that
    /// stable format lets Foundation find top-level snapshot separators in
    /// native code instead of asking Swift to inspect every byte of a 500 MB
    /// file. The structural streaming parser below remains the fallback for
    /// compact or externally modified archives.
    private func forEachPrettyPrintedLegacySnapshot(
        _ body: (LibrarySnapshot) throws -> Void
    ) throws -> Bool {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let arrayMarker = Data("\"snapshots\" : [\n    {".utf8)
        guard let markerRange = data.range(of: arrayMarker) else { return false }

        let objectSeparator = Data(",\n    {".utf8)
        let arrayTerminator = Data("\n    }\n  ]".utf8)
        var objectStart = markerRange.upperBound - 1

        while objectStart < data.endIndex {
            let searchRange = objectStart..<data.endIndex
            let separatorRange = data.range(of: objectSeparator, options: [], in: searchRange)
            let terminatorRange = data.range(of: arrayTerminator, options: [], in: searchRange)

            let objectEnd: Data.Index
            let nextStart: Data.Index?
            if let separatorRange,
               terminatorRange.map({ separatorRange.lowerBound < $0.lowerBound }) ?? true {
                objectEnd = separatorRange.lowerBound
                nextStart = separatorRange.upperBound - 1
            } else if let terminatorRange {
                objectEnd = terminatorRange.lowerBound + Data("\n    }".utf8).count
                nextStart = nil
            } else {
                throw LegacyStreamError.truncatedSnapshot
            }

            let snapshotData = data.subdata(in: objectStart..<objectEnd)
            try body(JSONDecoder.playCount.decode(LibrarySnapshot.self, from: snapshotData))
            guard let nextStart else { break }
            objectStart = nextStart
        }
        return true
    }

    @discardableResult
    private func saveLocked(_ stored: StoredSnapshots) -> Bool {
        guard !ledgerReadUnavailable, !ledgerLoadRetryPending, !legacyArchiveReadRetryPending else {
            #if DEBUG
            print("Skipped recap save because the existing ledger could not be loaded")
            #endif
            return false
        }
        do {
            var ledgerStored = stored
            ledgerStored.schemaVersion = 3
            guard persistenceWriteAllowed() else {
                throw CocoaError(.fileWriteUnknown)
            }
            let ledger = LedgerDatabase(url: ledgerURL)
            try ledger.save(ledgerStored)
            try writeSummaryCache(for: ledgerStored)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                guard let verified = try ledger.load(),
                      verified.snapshots.map(\.syncIdentifier) == ledgerStored.snapshots.map(\.syncIdentifier),
                      verified.monthlyLedgers == ledgerStored.monthlyLedgers,
                      verified.syncedRecaps == ledgerStored.syncedRecaps,
                      verified.syncedYearlyRecaps == ledgerStored.syncedYearlyRecaps else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                try markLedgerAuthoritative()
                let retiredLegacyArchive = try retireLegacyArchiveIfPresent()
                if let retiredLegacyArchive {
                    try? FileManager.default.removeItem(at: retiredLegacyArchive)
                }
            } else {
                try markLedgerAuthoritative()
            }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                cleanUpQuarantinedLedgerFiles()
            }
            persistenceSavePending = false
            loadedSnapshots = ledgerStored
            return true
        } catch {
            // A failed merge/save must also close the Cloud upload gate. Otherwise
            // sync could prune the only remote copy of data that never reached disk.
            persistenceSavePending = true
            loadedSnapshots = stored
            #if DEBUG
            print("Failed to save monthly recap ledger: \(error)")
            #endif
            return false
        }
    }

    private func writeSummaryCache(for stored: StoredSnapshots) throws {
        let summaries = SyncedRecapSummaries(
            monthlyRecaps: stored.syncedRecaps,
            yearlyRecaps: stored.syncedYearlyRecaps
        )
        let summaryData = try JSONEncoder.playCount.encode(summaries)
        if let currentData = try? Data(contentsOf: summaryFileURL),
           (try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: currentData)) != nil {
            // Rotate only a validated primary. Atomic replacement preserves
            // the last good backup if this write itself fails.
            try currentData.write(to: summaryBackupFileURL, options: [.atomic])
        }
        try summaryData.write(to: summaryFileURL, options: [.atomic])
    }

    private func markLedgerAuthoritative() throws {
        try Data("v1".utf8).write(to: ledgerAuthorityMarkerURL, options: [.atomic])
    }

    private func isPrimarySummaryCacheCurrent(for stored: StoredSnapshots) -> Bool {
        guard let data = try? Data(contentsOf: summaryFileURL) else { return false }
        let expected = SyncedRecapSummaries(
            monthlyRecaps: stored.syncedRecaps,
            yearlyRecaps: stored.syncedYearlyRecaps
        )
        return (try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: data)) == expected
    }

    private func resolvedSummaryCache() -> SyncedRecapSummaries? {
        func decoded(at url: URL) -> SyncedRecapSummaries? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder.playCount.decode(SyncedRecapSummaries.self, from: data)
        }
        let current = decoded(at: summaryFileURL)
        let backup = decoded(at: summaryBackupFileURL)
        guard current != nil || backup != nil else { return nil }
        var monthlyCandidates = current?.monthlyRecaps ?? []
        let currentMonths = Set(monthlyCandidates.map { Self.canonicalPersistedMonthStart($0.monthStart) })
        monthlyCandidates.append(contentsOf: (backup?.monthlyRecaps ?? []).filter {
            !currentMonths.contains(Self.canonicalPersistedMonthStart($0.monthStart))
        })
        var yearly = current?.yearlyRecaps ?? []
        let currentYears = Set(yearly.map(\.year))
        yearly.append(contentsOf: (backup?.yearlyRecaps ?? []).filter { !currentYears.contains($0.year) })
        return SyncedRecapSummaries(
            monthlyRecaps: Self.mergedSyncedRecaps(monthlyCandidates),
            yearlyRecaps: yearly.sorted { $0.year < $1.year }
        )
    }

    private func summaryCacheFallback() -> StoredSnapshots {
        let summaries = resolvedSummaryCache()
        let monthly = summaries?.monthlyRecaps ?? []
        return StoredSnapshots(
            schemaVersion: 3,
            counterReliabilityPolicyVersion: Self.currentCounterReliabilityPolicyVersion,
            snapshots: [],
            monthlyLedgers: monthly,
            syncedRecaps: monthly.map { $0.compacted() },
            syncedYearlyRecaps: summaries?.yearlyRecaps ?? []
        )
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
            albumArtist: "Self Check Artist",
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
            albumArtist: song.albumArtist,
            playCount: song.playCount,
            skipCount: song.skipCount,
            playbackDuration: song.playbackDuration,
            lastPlayedDate: song.lastPlayedDate,
            dateAdded: song.dateAdded,
            albumPersistentID: song.albumPersistentID,
            artistPersistentID: song.artistPersistentID,
            playbackStoreID: song.playbackStoreID
        )
    }

    var recordingFingerprint: String {
        [
            normalizedRecapIdentityComponent(title),
            normalizedRecapIdentityComponent(artist),
            normalizedRecapIdentityComponent(albumTitle),
            String(Int(playbackDuration.rounded()))
        ].joined(separator: "|")
    }
}

private extension UInt8 {
    var isJSONWhitespaceOrComma: Bool {
        self == Character(",").asciiValue ||
            self == Character(" ").asciiValue ||
            self == Character("\n").asciiValue ||
            self == Character("\r").asciiValue ||
            self == Character("\t").asciiValue
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

    var coverageSignature: String {
        let identifiers = songs.map(\.id).sorted().map(String.init).joined(separator: "|")
        return String(Self.stableHash(identifiers), radix: 16)
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
        encodedYearlyRecaps: Data? = nil,
        encodedUnattributedIntervals: Data? = nil
    ) -> RecapSnapshotSyncPayload? {
        let baseSnapshot = snapshotForSyncPayload(prioritySongIDs: prioritySongIDs)
        let snapshot = Self(
            capturedAt: baseSnapshot.capturedAt,
            reason: baseSnapshot.reason,
            appVersion: baseSnapshot.appVersion,
            scannedSongCount: baseSnapshot.scannedSongCount,
            deviceIdentifier: baseSnapshot.deviceIdentifier,
            aggregateCounters: baseSnapshot.aggregateCounters,
            songs: baseSnapshot.songs,
            encodedUnattributedIntervals: encodedUnattributedIntervals
        )
        guard let encodedSnapshot = try? JSONEncoder.playCount.encode(snapshot) else { return nil }
        let data: Data
        if encodedSnapshot.count <= MonthlyRecapSnapshotStore.maxSyncPayloadBytes {
            data = encodedSnapshot
        } else if let fallback = try? JSONEncoder.playCount.encode(baseSnapshot) {
            data = fallback
        } else {
            return nil
        }
        return RecapSnapshotSyncPayload(
            id: snapshot.syncIdentifier,
            capturedAt: snapshot.capturedAt,
            counterSignature: snapshot.counterSignature,
            reliabilityPolicyVersion: MonthlyRecapSnapshotStore.currentCounterReliabilityPolicyVersion,
            encodedSnapshot: data,
            encodedRecaps: encodedRecaps,
            encodedYearlyRecaps: encodedYearlyRecaps,
            encodedUnattributedIntervals: encodedUnattributedIntervals
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
        guard (syncPayload.reliabilityPolicyVersion ?? 0) >=
                MonthlyRecapSnapshotStore.currentCounterReliabilityPolicyVersion,
              let snapshot = try? JSONDecoder.playCount.decode(Self.self, from: syncPayload.encodedSnapshot),
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
    func recapMonthInterval(containing date: Date) -> DateInterval {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        gregorian.timeZone = timeZone
        return gregorian.dateInterval(of: .month, for: date)
            ?? DateInterval(start: gregorian.startOfDay(for: date), duration: 31 * 24 * 60 * 60)
    }

    func recapYear(containing date: Date) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        gregorian.timeZone = timeZone
        return gregorian.component(.year, from: date)
    }

    func recapMonth(containing date: Date) -> Int {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        gregorian.timeZone = timeZone
        return gregorian.component(.month, from: date)
    }

    func startOfMonth(containing date: Date) -> Date {
        let localBoundary = recapMonthInterval(containing: date).start
        var localGregorian = Calendar(identifier: .gregorian)
        localGregorian.locale = Locale(identifier: "en_US_POSIX")
        localGregorian.timeZone = timeZone
        let components = localGregorian.dateComponents([.year, .month], from: localBoundary)
        var stableCalendar = Calendar(identifier: .gregorian)
        stableCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return stableCalendar.date(from: DateComponents(
            timeZone: stableCalendar.timeZone,
            year: components.year,
            month: components.month,
            day: 1,
            hour: 12
        )) ?? startOfDay(for: date)
    }
}

private extension String {
    var normalizedArtworkKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
