import Foundation
import Combine
@preconcurrency import MediaPlayer
import AppIntents
import UIKit

struct TopSong: Identifiable {
    let id: UInt64
    let title: String
    let artist: String
    let albumTitle: String
    let playCount: Int
    let skipCount: Int
    let totalPlayDuration: TimeInterval
    let playbackDuration: TimeInterval
    let lastPlayedDate: Date?
    let dateAdded: Date?
    let artwork: MPMediaItemArtwork?
    let albumPersistentID: UInt64
    let artistPersistentID: UInt64
    let trackNumber: Int
}

struct TopAlbum: Identifiable {
    let id: UInt64
    let title: String
    let artist: String
    let playCount: Int
    let totalPlayDuration: TimeInterval
    let artwork: MPMediaItemArtwork?
    let artistPersistentID: UInt64
}

struct TopArtist: Identifiable {
    let id: UInt64
    let name: String
    let playCount: Int
    let totalPlayDuration: TimeInterval
    let artwork: MPMediaItemArtwork?
}

struct LibrarySummary {
    let songCount: Int
    let albumCount: Int
    let artistCount: Int
    let totalPlayCount: Int
    let totalListeningDuration: TimeInterval

    static let empty = LibrarySummary(
        songCount: 0,
        albumCount: 0,
        artistCount: 0,
        totalPlayCount: 0,
        totalListeningDuration: 0
    )

    init(songs: [TopSong], albums: [TopAlbum], artists: [TopArtist]) {
        songCount = songs.count
        albumCount = albums.count
        artistCount = artists.count
        totalPlayCount = songs.reduce(0) { $0 + $1.playCount }
        totalListeningDuration = songs.reduce(0) { $0 + $1.totalPlayDuration }
    }

    private init(
        songCount: Int,
        albumCount: Int,
        artistCount: Int,
        totalPlayCount: Int,
        totalListeningDuration: TimeInterval
    ) {
        self.songCount = songCount
        self.albumCount = albumCount
        self.artistCount = artistCount
        self.totalPlayCount = totalPlayCount
        self.totalListeningDuration = totalListeningDuration
    }
}

final class MediaLibraryManager: ObservableObject, @unchecked Sendable {
    
    static let shared = MediaLibraryManager()
    
    enum SortMetric: String, CaseIterable, Identifiable {
        case playCount
        case listenTime

        var id: String { rawValue }

        var toolbarLabel: String {
            switch self {
            case .playCount:
                return "Plays"
            case .listenTime:
                return "Time Played"
            }
        }

        var menuTitle: String {
            switch self {
            case .playCount:
                return "Number of Plays"
            case .listenTime:
                return "Time Listened"
            }
        }

        var systemImageName: String {
            switch self {
            case .playCount:
                return "number"
            case .listenTime:
                return "clock"
            }
        }

        func badgeText(playCount: Int, duration: TimeInterval) -> String {
            switch self {
            case .playCount:
                return Self.playCountFormatter.string(from: NSNumber(value: playCount)) ?? "\(playCount)"
            case .listenTime:
                return duration.formattedListeningMinutes
            }
        }

        func supplementaryDescription(playCount: Int, duration: TimeInterval) -> String {
            switch self {
            case .playCount:
                return "\(duration.formattedListeningMinutes) listened"
            case .listenTime:
                return "\(playCount) plays"
            }
        }

        private static let playCountFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = Locale.current.groupingSeparator
            return formatter
        }()
    }

    @Published private(set) var topSongs: [TopSong] = []
    @Published private(set) var topAlbums: [TopAlbum] = []
    @Published private(set) var topArtists: [TopArtist] = []
    @Published private(set) var librarySongs: [TopSong] = []
    @Published private(set) var libraryAlbums: [TopAlbum] = []
    @Published private(set) var libraryArtists: [TopArtist] = []
    @Published private(set) var librarySummary: LibrarySummary = .empty
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortMetric: SortMetric = .playCount {
        didSet {
            applySortAndLimit()
            updateLibraryIndexes(songs: librarySongs, albums: libraryAlbums, artists: libraryArtists)
        }
    }
    @Published private(set) var hasLoadedInitialSnapshot = false
    @Published private(set) var nowPlayingState: NowPlayingState?
    @Published private(set) var monthlyRecap: MonthlyRecap = .empty(for: Date())
    @Published private(set) var availableRecapMonths: [Date] = []

    private let fetchLimit: Int
    private lazy var mediaLibrary = MPMediaLibrary.default()
    private lazy var musicPlayer = MPMusicPlayerController.systemMusicPlayer
    private let snapshotStore: MonthlyRecapSnapshotStore
    private let recapCloudSyncService: RecapCloudSyncService?
    private var notificationObservers: [NSObjectProtocol] = []
    private var progressTimer: AnyCancellable?
    private var lastPlaybackDrivenRefresh: Date = .distantPast
    private var pendingSnapshotReason: RecapSnapshotReason?
    private let playbackRefreshInterval: TimeInterval = 20
    private var recapCache: [Date: MonthlyRecap] = [:]
    private var yearlyRecapCache: [Int: MonthlyRecap] = [:]
    private var yearlyMonthlyHighlightsCache: [Int: [YearlyRecapMonthlyHighlight]] = [:]
    private var isRecapCloudSyncInFlight = false
    private var pendingRecapCloudSync = false
    private var songsByPersistentID: [UInt64: TopSong] = [:]
    private var albumsByPersistentID: [UInt64: TopAlbum] = [:]
    private var artistsByPersistentID: [UInt64: TopArtist] = [:]
    private var songsByTitleArtistKey: [String: TopSong] = [:]
    private var albumsByTitleArtistKey: [String: TopAlbum] = [:]
    private var artistsByNameKey: [String: TopArtist] = [:]
    private var songsByAlbumID: [UInt64: [TopSong]] = [:]
    private var songsByAlbumKey: [String: [TopSong]] = [:]
    private var songsByArtistID: [UInt64: [TopSong]] = [:]
    private var songsByArtistKey: [String: [TopSong]] = [:]
    private var albumsByArtistID: [UInt64: [TopAlbum]] = [:]
    private var albumsByArtistKey: [String: [TopAlbum]] = [:]
    private var songPlayCountRanks: [UInt64: Int] = [:]
    private var songListenTimeRanks: [UInt64: Int] = [:]
    private var albumPlayCountRanks: [UInt64: Int] = [:]
    private var albumListenTimeRanks: [UInt64: Int] = [:]
    private var artistPlayCountRanks: [UInt64: Int] = [:]
    private var artistListenTimeRanks: [UInt64: Int] = [:]

    init(
        fetchLimit: Int = 0,
        snapshotStore: MonthlyRecapSnapshotStore = MonthlyRecapSnapshotStore(),
        recapCloudSyncService: RecapCloudSyncService? = MediaLibraryManager.defaultRecapCloudSyncService(),
        startsAutomatically: Bool = true
    ) {
        self.fetchLimit = fetchLimit
        self.snapshotStore = snapshotStore
        self.recapCloudSyncService = recapCloudSyncService

        #if DEBUG
        if Self.isScreenshotModeEnabled {
            authorizationStatus = .authorized
            monthlyRecap = .empty(for: Date())
            loadScreenshotFixture()
            return
        }
        #endif

        authorizationStatus = MPMediaLibrary.authorizationStatus()
        monthlyRecap = self.snapshotStore.currentMonthRecap()
        availableRecapMonths = self.snapshotStore.availableMonthStarts()

        guard startsAutomatically else {
            return
        }

        mediaLibrary.beginGeneratingLibraryChangeNotifications()
        musicPlayer.beginGeneratingPlaybackNotifications()
        configureObservers()
        updateNowPlayingState()

        if authorizationStatus == .authorized {
            refreshTopItems()
        }
        scheduleRecapCloudSync()
    }

    #if DEBUG
    func debugLoadLibraryFixture(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist]
    ) {
        librarySongs = songs
        libraryAlbums = albums
        libraryArtists = artists
        librarySummary = LibrarySummary(songs: songs, albums: albums, artists: artists)
        applySortAndLimit()
        updateLibraryIndexes(songs: songs, albums: albums, artists: artists)
        hasLoadedInitialSnapshot = true
    }
    #endif

    deinit {
        teardownObservers()
        mediaLibrary.endGeneratingLibraryChangeNotifications()
        musicPlayer.endGeneratingPlaybackNotifications()
    }

    func requestAuthorizationIfNeeded() {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            authorizationStatus = .authorized
            return
        }
        #endif

        let currentStatus = MPMediaLibrary.authorizationStatus()
        if authorizationStatus != currentStatus {
            authorizationStatus = currentStatus
        }

        switch currentStatus {
        case .notDetermined:
            isLoading = true
            MPMediaLibrary.requestAuthorization { [weak self] status in
                guard let self else { return }

                DispatchQueue.main.async {
                    self.authorizationStatus = status

                    if status == .authorized {
                        self.refreshTopItems()
                    } else {
                        self.isLoading = false
                        if status == .denied || status == .restricted {
                            self.errorMessage = "Media library access is required to show listening data."
                        }
                    }
                }
            }
        case .authorized:
            refreshTopItems()
        case .denied, .restricted:
            isLoading = false
            errorMessage = "Media library access is required to show listening data."
        default:
            break
        }
    }

    private static func defaultRecapCloudSyncService() -> RecapCloudSyncService? {
        #if DEBUG
        if isScreenshotModeEnabled {
            return nil
        }
        #endif

        return RecapCloudSyncService.live()
    }

    func refreshTopItems() {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            loadScreenshotFixture()
            return
        }
        #endif

        refreshTopItems(snapshotReason: .manualRefresh)
    }

    func refreshForRecap(reason: RecapSnapshotReason) {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            loadScreenshotFixture()
            return
        }
        #endif

        refreshTopItems(snapshotReason: reason)
    }

    func refreshForRecapSequence(reason: RecapSnapshotReason) {
        refreshForRecap(reason: reason)

        for delay in [8.0, 30.0, 90.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshForRecap(reason: .delayedForeground)
            }
        }
    }

    func syncRecapFromCloud() {
        scheduleRecapCloudSync()
    }

    @discardableResult
    func recordBackgroundRecapSnapshot(reason: RecapSnapshotReason = .backgroundRefresh) async -> Bool {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            await MainActor.run {
                self.loadScreenshotFixture()
            }
            return true
        }
        #endif

        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            return false
        }

        let result = await Task.detached(priority: .utility) { [snapshotStore] in
            let songs = Self.fetchTopSongs()
            let albums = Self.fetchTopAlbums()
            let artists = Self.fetchTopArtists()
            let recap = snapshotStore.record(songs: songs, albums: albums, artists: artists, at: Date(), reason: reason)
            return (songs, albums, artists, recap)
        }.value

        await MainActor.run {
            self.invalidateRecapCaches()
            self.librarySongs = result.0
            self.libraryAlbums = result.1
            self.libraryArtists = result.2
            self.librarySummary = LibrarySummary(songs: result.0, albums: result.1, artists: result.2)
            self.monthlyRecap = result.3
            self.availableRecapMonths = self.snapshotStore.availableMonthStarts()
            self.applySortAndLimit()
            self.updateLibraryIndexes(songs: result.0, albums: result.1, artists: result.2)
            self.hasLoadedInitialSnapshot = true
            self.scheduleRecapCloudSync()
        }

        return true
    }

    func recap(forMonthContaining date: Date) -> MonthlyRecap {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            return Self.screenshotRecap(from: Self.screenshotSongs, monthStart: date)
        }
        #endif

        let monthStart = Calendar.current.startOfMonth(containing: date)
        if let cached = recapCache[monthStart] {
            return cached
        }

        return snapshotStore.recap(
            forMonthContaining: date,
            sourceSongs: librarySongs,
            sourceAlbums: libraryAlbums,
            sourceArtists: libraryArtists
        ).caching(in: &recapCache, for: monthStart)
    }

    func recaps(forMonthsContaining dates: [Date]) -> [MonthlyRecap] {
        let monthStarts = dates.map { Calendar.current.startOfMonth(containing: $0) }
        let missingMonths = monthStarts.filter { recapCache[$0] == nil }

        if !missingMonths.isEmpty {
            let recaps = snapshotStore.recaps(
                forMonthsContaining: missingMonths,
                sourceSongs: librarySongs,
                sourceAlbums: libraryAlbums,
                sourceArtists: libraryArtists
            )

            for (monthStart, recap) in zip(missingMonths, recaps) {
                recapCache[monthStart] = recap
            }
        }

        return monthStarts.map { recapCache[$0] ?? .empty(for: $0) }
    }

    func yearlyRecap(for year: Int) -> MonthlyRecap {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            return Self.screenshotRecap(from: Self.screenshotSongs)
        }
        #endif

        if let cached = yearlyRecapCache[year] {
            return cached
        }

        let yearMonths = months(in: year)
        let recap = snapshotStore.syncedYearlyRecap(
            for: year,
            sourceSongs: librarySongs,
            sourceAlbums: libraryAlbums,
            sourceArtists: libraryArtists
        ) ?? Self.yearlyRecap(
                for: year,
                months: yearMonths,
                monthlyRecaps: recaps(forMonthsContaining: yearMonths),
                fallbackMonth: monthlyRecap.monthStart,
                fallbackRecap: monthlyRecap
            )
        yearlyRecapCache[year] = recap
        return recap
    }

    func yearlyMonthlyHighlights(for year: Int) -> [YearlyRecapMonthlyHighlight] {
        if let cached = yearlyMonthlyHighlightsCache[year] {
            return cached
        }

        let months = months(in: year)
        let highlights = zip(months, recaps(forMonthsContaining: months))
            .map { YearlyRecapMonthlyHighlight(month: $0.0, recap: $0.1) }
            .filter { $0.recap.hasActivity }
        yearlyMonthlyHighlightsCache[year] = highlights
        return highlights
    }

    private func months(in year: Int) -> [Date] {
        let source = availableRecapMonths.isEmpty ? [monthlyRecap.monthStart] : availableRecapMonths
        return Array(Set(source.map { Calendar.current.startOfMonth(containing: $0) }))
            .filter { Calendar.current.component(.year, from: $0) == year }
            .sorted()
    }

    private func invalidateRecapCaches() {
        recapCache.removeAll()
        yearlyRecapCache.removeAll()
        yearlyMonthlyHighlightsCache.removeAll()
    }

    private func scheduleRecapCloudSync() {
        guard let recapCloudSyncService else { return }
        guard !isRecapCloudSyncInFlight else {
            pendingRecapCloudSync = true
            return
        }

        isRecapCloudSyncInFlight = true

        Task { [weak self, snapshotStore, recapCloudSyncService] in
            _ = await recapCloudSyncService.sync(snapshotStore: snapshotStore)

            let shouldSyncAgain = await MainActor.run { [weak self] in
                guard let self else { return false }
                self.isRecapCloudSyncInFlight = false
                self.invalidateRecapCaches()
                self.monthlyRecap = self.recap(forMonthContaining: Date())
                self.availableRecapMonths = self.snapshotStore.availableMonthStarts()
                let shouldSyncAgain = self.pendingRecapCloudSync
                self.pendingRecapCloudSync = false
                return shouldSyncAgain
            }

            if shouldSyncAgain {
                await MainActor.run { [weak self] in
                    self?.scheduleRecapCloudSync()
                }
            }
        }
    }

    func recapDebugSummary() -> String {
        [
            snapshotStore.debugSummary(),
            recapArtworkDebugSummary()
        ].joined(separator: "\n\n")
    }

    #if DEBUG
    func runRecapSelfCheck() -> String {
        snapshotStore.debugRunSelfCheck()
    }
    #endif

    private func recapArtworkDebugSummary() -> String {
        let recap = monthlyRecap
        let topSongArtworkCount = recap.topSongs.filter { $0.artwork != nil }.count
        let topAlbumArtworkCount = recap.topAlbums.filter { $0.artwork != nil }.count
        let topArtistArtworkCount = recap.topArtists.filter { $0.artwork != nil }.count
        let gainerArtworkCount = recap.biggestGainers.filter { $0.artwork != nil }.count
        let newSongArtworkCount = recap.topNewSongs.filter { $0.artwork != nil }.count

        func missingSongs(_ songs: [MonthlyRecap.RankedSong]) -> String {
            let missing = songs.filter { $0.artwork == nil }.prefix(8)
            guard !missing.isEmpty else { return "none" }
            return missing.map { "\($0.title) - \($0.artist)" }.joined(separator: ", ")
        }

        func missingMovementSongs(_ songs: [MonthlyRecap.MovementSong]) -> String {
            let missing = songs.filter { $0.artwork == nil }.prefix(8)
            guard !missing.isEmpty else { return "none" }
            return missing.map { "\($0.title) - \($0.artist)" }.joined(separator: ", ")
        }

        func missingGroups(_ groups: [MonthlyRecap.RankedGroup]) -> String {
            let missing = groups.filter { $0.artwork == nil }.prefix(8)
            guard !missing.isEmpty else { return "none" }
            return missing.map { "\($0.title) - \($0.subtitle)" }.joined(separator: ", ")
        }

        return """
        Recap artwork:
        Top songs artwork: \(topSongArtworkCount)/\(recap.topSongs.count)
        Top albums artwork: \(topAlbumArtworkCount)/\(recap.topAlbums.count)
        Top artists artwork: \(topArtistArtworkCount)/\(recap.topArtists.count)
        Biggest gainers artwork: \(gainerArtworkCount)/\(recap.biggestGainers.count)
        Top new songs artwork: \(newSongArtworkCount)/\(recap.topNewSongs.count)
        Live library songs/albums/artists: \(librarySongs.count)/\(libraryAlbums.count)/\(libraryArtists.count)
        Visible top songs/albums/artists: \(topSongs.count)/\(topAlbums.count)/\(topArtists.count)
        Missing top song art: \(missingSongs(recap.topSongs))
        Missing top album art: \(missingGroups(recap.topAlbums))
        Missing top artist art: \(missingGroups(recap.topArtists))
        Missing gainer art: \(missingMovementSongs(recap.biggestGainers))
        Missing new song art: \(missingSongs(recap.topNewSongs))
        """
    }

    private static func yearlyRecap(
        for year: Int,
        months: [Date],
        monthlyRecaps: [MonthlyRecap],
        fallbackMonth: Date,
        fallbackRecap: MonthlyRecap
    ) -> MonthlyRecap {
        MonthlyRecap.yearly(
            for: year,
            months: months,
            monthlyRecaps: monthlyRecaps,
            fallbackMonth: fallbackMonth,
            fallbackRecap: fallbackRecap
        )
    }

    #if DEBUG
    static func debugYearlyRecap(
        for year: Int,
        months: [Date],
        monthlyRecaps: [MonthlyRecap],
        fallbackMonth: Date,
        fallbackRecap: MonthlyRecap
    ) -> MonthlyRecap {
        MonthlyRecap.yearly(
            for: year,
            months: months,
            monthlyRecaps: monthlyRecaps,
            fallbackMonth: fallbackMonth,
            fallbackRecap: fallbackRecap
        )
    }
    #endif

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
        let currentRank: Int
        let previousRank: Int
        let artwork: MPMediaItemArtwork?
        var playDelta: Int
        var rankChange: Int

        init(song: MonthlyRecap.MovementSong) {
            id = song.id
            title = song.title
            artist = song.artist
            currentRank = song.currentRank
            previousRank = song.previousRank ?? song.currentRank
            artwork = song.artwork
            playDelta = 0
            rankChange = 0
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

    private func refreshTopItems(snapshotReason: RecapSnapshotReason) {
        let currentStatus = MPMediaLibrary.authorizationStatus()
        if authorizationStatus != currentStatus {
            authorizationStatus = currentStatus
        }

        guard currentStatus == .authorized else {
            isLoading = false
            errorMessage = "Media library access is required to show listening data."
            return
        }

        guard !isLoading else {
            pendingSnapshotReason = snapshotReason
            return
        }

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let songs = Self.fetchTopSongs()
            let albums = Self.fetchTopAlbums()
            let artists = Self.fetchTopArtists()
            let recap = self.snapshotStore.record(songs: songs, albums: albums, artists: artists, at: Date(), reason: snapshotReason)

            DispatchQueue.main.async {
                self.invalidateRecapCaches()
                self.librarySongs = songs
                self.libraryAlbums = albums
                self.libraryArtists = artists
                self.librarySummary = LibrarySummary(songs: songs, albums: albums, artists: artists)
                self.monthlyRecap = recap
                self.availableRecapMonths = self.snapshotStore.availableMonthStarts()

                self.applySortAndLimit()
                self.updateLibraryIndexes(songs: songs, albums: albums, artists: artists)
                self.isLoading = false
                self.hasLoadedInitialSnapshot = true
                self.scheduleRecapCloudSync()

                if songs.isEmpty && albums.isEmpty && artists.isEmpty {
                    self.errorMessage = "We couldn't find any listening data in your media library."
                }

                if let pendingSnapshotReason = self.pendingSnapshotReason {
                    self.pendingSnapshotReason = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                        self?.refreshTopItems(snapshotReason: pendingSnapshotReason)
                    }
                }
            }
        }
    }

    private func handleMediaLibraryDidChange() {
        refreshForRecap(reason: .libraryChanged)
    }

    private func applySortAndLimit() {
        if fetchLimit > 0 {
            topSongs = Array(sortSongs(librarySongs).prefix(fetchLimit))
            topAlbums = Array(sortAlbums(libraryAlbums).prefix(fetchLimit))
            topArtists = Array(sortArtists(libraryArtists).prefix(fetchLimit))
        } else {
            // No limit - show all
            topSongs = sortSongs(librarySongs)
            topAlbums = sortAlbums(libraryAlbums)
            topArtists = sortArtists(libraryArtists)
        }
    }

    private func updateLibraryIndexes(songs: [TopSong], albums: [TopAlbum], artists: [TopArtist]) {
        songsByPersistentID = Dictionary(songs.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        albumsByPersistentID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        artistsByPersistentID = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        songsByTitleArtistKey = Dictionary(
            songs.map { (Self.titleArtistKey(title: $0.title, artist: $0.artist), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        albumsByTitleArtistKey = Dictionary(
            albums.map { (Self.titleArtistKey(title: $0.title, artist: $0.artist), $0) },
            uniquingKeysWith: { current, _ in current }
        )
        artistsByNameKey = Dictionary(
            artists.map { (Self.normalizedLookupKey($0.name), $0) },
            uniquingKeysWith: { current, _ in current }
        )

        songsByAlbumID = Dictionary(grouping: songs.filter { $0.albumPersistentID != 0 }, by: \.albumPersistentID)
            .mapValues(sortSongs)
        songsByAlbumKey = Dictionary(grouping: songs, by: { Self.titleArtistKey(title: $0.albumTitle, artist: $0.artist) })
            .mapValues(sortSongs)
        songsByArtistID = Dictionary(grouping: songs.filter { $0.artistPersistentID != 0 }, by: \.artistPersistentID)
            .mapValues(sortSongs)
        songsByArtistKey = Dictionary(grouping: songs, by: { Self.normalizedLookupKey($0.artist) })
            .mapValues(sortSongs)
        albumsByArtistID = Dictionary(grouping: albums.filter { $0.artistPersistentID != 0 }, by: \.artistPersistentID)
            .mapValues(sortAlbums)
        albumsByArtistKey = Dictionary(grouping: albums, by: { Self.normalizedLookupKey($0.artist) })
            .mapValues(sortAlbums)

        songPlayCountRanks = Self.rankMap(for: songs.sorted(by: Self.isHigherPlayCountSong).map(\.id))
        songListenTimeRanks = Self.rankMap(for: songs.sorted(by: Self.isHigherListenTimeSong).map(\.id))
        albumPlayCountRanks = Self.rankMap(for: albums.sorted(by: Self.isHigherPlayCountAlbum).map(\.id))
        albumListenTimeRanks = Self.rankMap(for: albums.sorted(by: Self.isHigherListenTimeAlbum).map(\.id))
        artistPlayCountRanks = Self.rankMap(for: artists.sorted(by: Self.isHigherPlayCountArtist).map(\.id))
        artistListenTimeRanks = Self.rankMap(for: artists.sorted(by: Self.isHigherListenTimeArtist).map(\.id))
    }

    func songs(for album: TopAlbum, limit: Int? = nil) -> [TopSong] {
        let sorted = songsForAlbum(album)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func songs(for artist: TopArtist, limit: Int? = nil) -> [TopSong] {
        let sorted = songsForArtist(artist)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func albums(for artist: TopArtist, limit: Int? = nil) -> [TopAlbum] {
        let sorted = albumsForArtist(artist)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func rank(of song: TopSong) -> Int? {
        topSongs.firstIndex(where: { $0.id == song.id }).map { $0 + 1 }
    }

    func rank(of album: TopAlbum) -> Int? {
        topAlbums.firstIndex(where: { $0.id == album.id }).map { $0 + 1 }
    }

    func rank(of artist: TopArtist) -> Int? {
        topArtists.firstIndex(where: { $0.id == artist.id }).map { $0 + 1 }
    }

    func song(withPersistentID id: UInt64) -> TopSong? {
        if let match = songsByPersistentID[id] {
            return match
        }

        return topSongs.first(where: { $0.id == id })
    }

    func song(matchingTitle title: String, artist: String) -> TopSong? {
        songsByTitleArtistKey[Self.titleArtistKey(title: title, artist: artist)]
    }

    func playCountRank(of song: TopSong) -> Int? {
        songPlayCountRanks[song.id]
    }

    func listenTimeRank(of song: TopSong) -> Int? {
        songListenTimeRanks[song.id]
    }

    func playCountRank(of album: TopAlbum) -> Int? {
        albumPlayCountRanks[album.id]
    }

    func listenTimeRank(of album: TopAlbum) -> Int? {
        albumListenTimeRanks[album.id]
    }

    func playCountRank(of artist: TopArtist) -> Int? {
        artistPlayCountRanks[artist.id]
    }

    func listenTimeRank(of artist: TopArtist) -> Int? {
        artistListenTimeRanks[artist.id]
    }

    func album(withPersistentID id: UInt64) -> TopAlbum? {
        if let match = albumsByPersistentID[id] {
            return match
        }

        return topAlbums.first(where: { $0.id == id })
    }

    func album(matchingTitle title: String, artist: String) -> TopAlbum? {
        albumsByTitleArtistKey[Self.titleArtistKey(title: title, artist: artist)]
    }

    func artist(withPersistentID id: UInt64) -> TopArtist? {
        if let match = artistsByPersistentID[id] {
            return match
        }

        return topArtists.first(where: { $0.id == id })
    }

    func artist(matchingName name: String) -> TopArtist? {
        artistsByNameKey[Self.normalizedLookupKey(name)]
    }

    func artworkForAlbum(title: String, artist: String) -> MPMediaItemArtwork? {
        if let artwork = album(matchingTitle: title, artist: artist)?.artwork {
            return artwork
        }

        return songsByAlbumKey[Self.titleArtistKey(title: title, artist: artist)]?.first?.artwork
    }

    func artworkForArtist(name: String) -> MPMediaItemArtwork? {
        if let artwork = artist(matchingName: name)?.artwork {
            return artwork
        }

        return songsByArtistKey[Self.normalizedLookupKey(name)]?.first?.artwork
    }

    private func songsForAlbum(_ album: TopAlbum) -> [TopSong] {
        var candidates: [TopSong] = []

        if album.id != 0, let songs = songsByAlbumID[album.id] {
            candidates.append(contentsOf: songs)
        }

        let albumKeyMatches = songsByAlbumKey[Self.titleArtistKey(title: album.title, artist: album.artist)] ?? []
        candidates.append(contentsOf: albumKeyMatches.filter { song in
            song.albumPersistentID == 0 && (
                (album.artistPersistentID != 0 && song.artistPersistentID == album.artistPersistentID) ||
                song.artist.localizedCaseInsensitiveCompare(album.artist) == .orderedSame
            )
        })

        return sortSongs(Self.deduplicated(candidates))
    }

    private func songsForArtist(_ artist: TopArtist) -> [TopSong] {
        var candidates: [TopSong] = []

        if artist.id != 0, let songs = songsByArtistID[artist.id] {
            candidates.append(contentsOf: songs)
        }

        let artistNameMatches = songsByArtistKey[Self.normalizedLookupKey(artist.name)] ?? []
        candidates.append(contentsOf: artistNameMatches.filter { $0.artistPersistentID == 0 })

        return sortSongs(Self.deduplicated(candidates))
    }

    private func albumsForArtist(_ artist: TopArtist) -> [TopAlbum] {
        var candidates: [TopAlbum] = []

        if artist.id != 0, let albums = albumsByArtistID[artist.id] {
            candidates.append(contentsOf: albums)
        }

        candidates.append(contentsOf: albumsByArtistKey[Self.normalizedLookupKey(artist.name)] ?? [])

        return sortAlbums(Self.deduplicated(candidates))
    }

    private static func titleArtistKey(title: String, artist: String) -> String {
        "\(normalizedLookupKey(title))|\(normalizedLookupKey(artist))"
    }

    private static func normalizedLookupKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func deduplicated<T: Identifiable>(_ values: [T]) -> [T] where T.ID == UInt64 {
        var seen: Set<UInt64> = []
        return values.filter { value in
            seen.insert(value.id).inserted
        }
    }

    private static func rankMap(for ids: [UInt64]) -> [UInt64: Int] {
        Dictionary(ids.enumerated().map { index, id in
            (id, index + 1)
        }, uniquingKeysWith: { current, _ in current })
    }

    func togglePlayback() {
        switch musicPlayer.playbackState {
        case .playing:
            musicPlayer.pause()
        default:
            musicPlayer.play()
        }
    }

    func skipForward() {
        musicPlayer.skipToNextItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNowPlayingState()
        }
    }

    func play(song: TopSong) {
        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: song.id),
            forProperty: MPMediaItemPropertyPersistentID
        )

        let query = MPMediaQuery.songs()
        query.addFilterPredicate(predicate)

        guard let items = query.items, !items.isEmpty else {
            return
        }

        let collection = MPMediaItemCollection(items: items)
        musicPlayer.setQueue(with: collection)
        musicPlayer.nowPlayingItem = items.first
        musicPlayer.play()
        updateNowPlayingState()
    }

    func play(album: TopAlbum) {
        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: album.id),
            forProperty: MPMediaItemPropertyAlbumPersistentID
        )

        let query = MPMediaQuery.songs()
        query.addFilterPredicate(predicate)

        guard let items = query.items, !items.isEmpty else {
            return
        }

        let sortedItems = items.sorted { lhs, rhs in
            if lhs.discNumber != rhs.discNumber {
                return lhs.discNumber < rhs.discNumber
            }
            if lhs.albumTrackNumber != rhs.albumTrackNumber {
                return lhs.albumTrackNumber < rhs.albumTrackNumber
            }
            return (lhs.title ?? "").localizedCaseInsensitiveCompare(rhs.title ?? "") == .orderedAscending
        }

        let collection = MPMediaItemCollection(items: sortedItems)
        musicPlayer.setQueue(with: collection)
        musicPlayer.nowPlayingItem = sortedItems.first
        musicPlayer.play()
        updateNowPlayingState()
    }

    func play(artist: TopArtist) {
        let query = MPMediaQuery.songs()

        if artist.id != 0 {
            let predicate = MPMediaPropertyPredicate(
                value: NSNumber(value: artist.id),
                forProperty: MPMediaItemPropertyArtistPersistentID
            )
            query.addFilterPredicate(predicate)
        } else {
            let predicate = MPMediaPropertyPredicate(
                value: artist.name,
                forProperty: MPMediaItemPropertyArtist,
                comparisonType: .equalTo
            )
            query.addFilterPredicate(predicate)
        }

        guard let items = query.items, !items.isEmpty else {
            return
        }

        let collection = MPMediaItemCollection(items: items)
        musicPlayer.setQueue(with: collection)
        musicPlayer.nowPlayingItem = items.first
        musicPlayer.play()
        updateNowPlayingState()
    }

    private func sortSongs(_ songs: [TopSong]) -> [TopSong] {
        songs.sorted { lhs, rhs in
            switch sortMetric {
            case .playCount:
                return Self.isHigherPlayCountSong(lhs, rhs)
            case .listenTime:
                return Self.isHigherListenTimeSong(lhs, rhs)
            }
        }
    }

    private static func isHigherPlayCountSong(_ lhs: TopSong, _ rhs: TopSong) -> Bool {
        if lhs.playCount == rhs.playCount {
            if lhs.totalPlayDuration == rhs.totalPlayDuration {
                return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
            }
            return lhs.totalPlayDuration > rhs.totalPlayDuration
        }
        return lhs.playCount > rhs.playCount
    }

    private static func isHigherListenTimeSong(_ lhs: TopSong, _ rhs: TopSong) -> Bool {
        if lhs.totalPlayDuration == rhs.totalPlayDuration {
            if lhs.playCount == rhs.playCount {
                return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
            }
            return lhs.playCount > rhs.playCount
        }
        return lhs.totalPlayDuration > rhs.totalPlayDuration
    }

    private func configureObservers() {
        let center = NotificationCenter.default

        let libraryObserver = center.addObserver(forName: .MPMediaLibraryDidChange, object: mediaLibrary, queue: .main) { [weak self] _ in
            self?.handleMediaLibraryDidChange()
        }

        let itemObserver = center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: musicPlayer, queue: .main) { [weak self] _ in
            self?.handleNowPlayingChange()
        }

        let playbackObserver = center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: musicPlayer, queue: .main) { [weak self] _ in
            self?.handlePlaybackStateChange()
        }

        notificationObservers = [libraryObserver, itemObserver, playbackObserver]
    }

    private func teardownObservers() {
        let center = NotificationCenter.default
        for observer in notificationObservers {
            center.removeObserver(observer)
        }
        notificationObservers.removeAll()
        progressTimer?.cancel()
        progressTimer = nil
    }

    private func handleNowPlayingChange() {
        updateNowPlayingState()
        refreshFromPlaybackIfNeeded(force: true)
    }

    private func handlePlaybackStateChange() {
        updateNowPlayingState()

        switch musicPlayer.playbackState {
        case .playing:
            startProgressUpdates()
            refreshFromPlaybackIfNeeded()
        default:
            stopProgressUpdates()
            refreshFromPlaybackIfNeeded(force: true)
        }
    }

    private func startProgressUpdates() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateNowPlayingState()
                self?.refreshFromPlaybackIfNeeded()
            }
    }

    private func stopProgressUpdates() {
        progressTimer?.cancel()
        progressTimer = nil
    }

    private func updateNowPlayingState() {
        let item = musicPlayer.nowPlayingItem
        let playbackState = musicPlayer.playbackState
        let playbackTime = musicPlayer.currentPlaybackTime
        let currentTime = playbackTime.isFinite ? max(playbackTime, 0) : 0

        guard let item else {
            DispatchQueue.main.async {
                self.nowPlayingState = nil
            }
            stopProgressUpdates()
            return
        }

        let rawTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = item.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        let subtitle: String
        switch (artist, album) {
        case let (artist?, album?) where !artist.isEmpty && !album.isEmpty:
            subtitle = "\(artist) — \(album)"
        case let (artist?, _) where !artist.isEmpty:
            subtitle = artist
        case let (_, album?) where !album.isEmpty:
            subtitle = album
        default:
            subtitle = ""
        }

        let duration = item.playbackDuration.isFinite ? max(item.playbackDuration, 0) : 0
        let playCount = item.playCount
        let skipCount = item.skipCount
        let totalPlayDuration = Double(playCount) * duration

        let resolvedTitle = rawTitle.nonEmptyFallback("Unknown Title")
        let resolvedArtist = artist?.nonEmptyFallback("Unknown Artist") ?? "Unknown Artist"
        let resolvedAlbum = album?.nonEmptyFallback("Unknown Album") ?? "Unknown Album"

        let topSong = TopSong(
            id: item.persistentID,
            title: resolvedTitle,
            artist: resolvedArtist,
            albumTitle: resolvedAlbum,
            playCount: playCount,
            skipCount: skipCount,
            totalPlayDuration: totalPlayDuration,
            playbackDuration: duration,
            lastPlayedDate: item.safeLastPlayedDate,
            dateAdded: item.safeDateAdded,
            artwork: item.artwork,
            albumPersistentID: item.albumPersistentID,
            artistPersistentID: item.artistPersistentID,
            trackNumber: item.albumTrackNumber
        )

        let state = NowPlayingState(
            title: resolvedTitle,
            subtitle: subtitle,
            artwork: item.artwork,
            duration: duration,
            currentTime: currentTime,
            isPlaying: playbackState == .playing,
            playCount: playCount,
            song: topSong
        )

        DispatchQueue.main.async {
            self.nowPlayingState = state
        }

        if playbackState == .playing {
            startProgressUpdates()
        }
    }

    private func refreshFromPlaybackIfNeeded(force: Bool = false) {
        guard authorizationStatus == .authorized else { return }
        guard !isLoading else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastPlaybackDrivenRefresh) < playbackRefreshInterval {
            return
        }

        lastPlaybackDrivenRefresh = now
        refreshForRecap(reason: .playbackChanged)
    }

    private func sortAlbums(_ albums: [TopAlbum]) -> [TopAlbum] {
        albums.sorted { lhs, rhs in
            switch sortMetric {
            case .playCount:
                return Self.isHigherPlayCountAlbum(lhs, rhs)
            case .listenTime:
                return Self.isHigherListenTimeAlbum(lhs, rhs)
            }
        }
    }

    private func sortArtists(_ artists: [TopArtist]) -> [TopArtist] {
        artists.sorted { lhs, rhs in
            switch sortMetric {
            case .playCount:
                return Self.isHigherPlayCountArtist(lhs, rhs)
            case .listenTime:
                return Self.isHigherListenTimeArtist(lhs, rhs)
            }
        }
    }

    private static func isHigherPlayCountAlbum(_ lhs: TopAlbum, _ rhs: TopAlbum) -> Bool {
        if lhs.playCount == rhs.playCount {
            if lhs.totalPlayDuration == rhs.totalPlayDuration {
                return lhs.title < rhs.title
            }
            return lhs.totalPlayDuration > rhs.totalPlayDuration
        }
        return lhs.playCount > rhs.playCount
    }

    private static func isHigherListenTimeAlbum(_ lhs: TopAlbum, _ rhs: TopAlbum) -> Bool {
        if lhs.totalPlayDuration == rhs.totalPlayDuration {
            if lhs.playCount == rhs.playCount {
                return lhs.title < rhs.title
            }
            return lhs.playCount > rhs.playCount
        }
        return lhs.totalPlayDuration > rhs.totalPlayDuration
    }

    private static func isHigherPlayCountArtist(_ lhs: TopArtist, _ rhs: TopArtist) -> Bool {
        if lhs.playCount == rhs.playCount {
            if lhs.totalPlayDuration == rhs.totalPlayDuration {
                return lhs.name < rhs.name
            }
            return lhs.totalPlayDuration > rhs.totalPlayDuration
        }
        return lhs.playCount > rhs.playCount
    }

    private static func isHigherListenTimeArtist(_ lhs: TopArtist, _ rhs: TopArtist) -> Bool {
        if lhs.totalPlayDuration == rhs.totalPlayDuration {
            if lhs.playCount == rhs.playCount {
                return lhs.name < rhs.name
            }
            return lhs.playCount > rhs.playCount
        }
        return lhs.totalPlayDuration > rhs.totalPlayDuration
    }

    private static func fetchTopSongs() -> [TopSong] {
        let query = MPMediaQuery.songs()
        let items = query.items ?? []

        return items
            .filter { $0.playCount > 0 }
            .compactMap { item in
                guard item.persistentID != 0 else { return nil }
                let totalDuration = Double(item.playCount) * item.playbackDuration
                return TopSong(
                    id: item.persistentID,
                    title: item.title ?? "Unknown Title",
                    artist: item.artist ?? "Unknown Artist",
                    albumTitle: item.albumTitle ?? "Unknown Album",
                    playCount: item.playCount,
                    skipCount: item.skipCount,
                    totalPlayDuration: totalDuration,
                    playbackDuration: item.playbackDuration,
                    lastPlayedDate: item.safeLastPlayedDate,
                    dateAdded: item.safeDateAdded,
                    artwork: item.artwork,
                    albumPersistentID: item.albumPersistentID,
                    artistPersistentID: item.artistPersistentID,
                    trackNumber: item.albumTrackNumber
                )
            }
    }

    private static func fetchTopAlbums() -> [TopAlbum] {
        let query = MPMediaQuery.albums()
        let collections = query.collections ?? []

        return collections.compactMap { collection in
            guard let representative = collection.representativeItem,
                  representative.albumPersistentID != 0 else { return nil }

            var playCount = 0
            var totalDuration: TimeInterval = 0

            for item in collection.items {
                playCount += item.playCount
                totalDuration += Double(item.playCount) * item.playbackDuration
            }

            guard playCount > 0 else { return nil }

            return TopAlbum(
                id: representative.albumPersistentID,
                title: representative.albumTitle ?? "Unknown Album",
                artist: representative.albumArtist ?? representative.artist ?? "Unknown Artist",
                playCount: playCount,
                totalPlayDuration: totalDuration,
                artwork: representative.artwork,
                artistPersistentID: representative.artistPersistentID
            )
        }
    }

    private static func fetchTopArtists() -> [TopArtist] {
        let query = MPMediaQuery.artists()
        let collections = query.collections ?? []

        return collections.compactMap { collection in
            guard let representative = collection.representativeItem,
                  representative.artistPersistentID != 0 else { return nil }

            var playCount = 0
            var totalDuration: TimeInterval = 0

            for item in collection.items {
                playCount += item.playCount
                totalDuration += Double(item.playCount) * item.playbackDuration
            }

            guard playCount > 0 else { return nil }

            return TopArtist(
                id: representative.artistPersistentID,
                name: representative.artist ?? "Unknown Artist",
                playCount: playCount,
                totalPlayDuration: totalDuration,
                artwork: representative.artwork
            )
        }
    }
}

extension MediaLibraryManager {
    struct NowPlayingState: Equatable {
        let title: String
        let subtitle: String
        let artwork: MPMediaItemArtwork?
        let duration: TimeInterval
        let currentTime: TimeInterval
        let isPlaying: Bool
        let playCount: Int
        let song: TopSong?

        var progress: Double {
            guard duration > 0 else { return 0 }
            return max(0, min(currentTime / duration, 1))
        }

        var formattedTimeRemaining: String {
            let remaining = max(duration - currentTime, 0)
            return "-\(remaining.formattedPlayback)"
        }

        var formattedElapsed: String {
            currentTime.formattedPlayback
        }

        static func == (lhs: NowPlayingState, rhs: NowPlayingState) -> Bool {
            let artworksEqual: Bool
            switch (lhs.artwork, rhs.artwork) {
            case (nil, nil):
                artworksEqual = true
            case let (left?, right?):
                artworksEqual = left === right
            default:
                artworksEqual = false
            }

            return lhs.title == rhs.title &&
                lhs.subtitle == rhs.subtitle &&
                artworksEqual &&
                lhs.duration == rhs.duration &&
                lhs.currentTime == rhs.currentTime &&
                lhs.isPlaying == rhs.isPlaying &&
                lhs.playCount == rhs.playCount &&
                lhs.song?.id == rhs.song?.id
        }
    }
}

private extension MonthlyRecap {
    func caching(in cache: inout [Date: MonthlyRecap], for monthStart: Date) -> MonthlyRecap {
        cache[monthStart] = self
        return self
    }
}

private extension MPMediaItem {
    var safeLastPlayedDate: Date? {
        value(forProperty: MPMediaItemPropertyLastPlayedDate) as? Date
    }

    var safeDateAdded: Date? {
        value(forProperty: MPMediaItemPropertyDateAdded) as? Date
    }
}

extension TimeInterval {
    var formattedPlayback: String {
        guard self > 0 else { return "0s" }
        if let formatted = TimeInterval.playbackFormatter.string(from: self) {
            return formatted
        }
        let seconds = Int(self.rounded())
        return "\(seconds)s"
    }

    static let playbackFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.dropLeading]
        return formatter
    }()

    var formattedListeningMinutes: String {
        guard self > 0 else { return "0 min" }

        let minutes = self / 60
        if minutes < 1 {
            return "<1 min"
        }

        return "\(Self.compactMinutesValue(minutes)) min"
    }

    private static func compactMinutesValue(_ minutes: Double) -> String {
        if minutes >= 1_000_000 {
            return "\(compactMinutesFormatter.string(from: NSNumber(value: minutes / 1_000_000)) ?? "1")M"
        }

        if minutes >= 1_000 {
            return "\(compactMinutesFormatter.string(from: NSNumber(value: minutes / 1_000)) ?? "1")k"
        }

        return wholeMinutesFormatter.string(from: NSNumber(value: minutes.rounded())) ?? "\(Int(minutes.rounded()))"
    }

    private static let compactMinutesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.positiveFormat = "#,##0.#"
        return formatter
    }()

    private static let wholeMinutesFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = Locale.current.groupingSeparator
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

extension String {
    func nonEmptyFallback(_ fallback: String) -> String {
        if self.isEmpty { return fallback }
        return self
    }
}

extension Optional where Wrapped == String {
    func nonEmptyFallback(_ fallback: String) -> String {
        guard let value = self else { return fallback }
        if value.isEmpty {
            return fallback
        }
        return value
    }
}

#if DEBUG
private extension Calendar {
    func screenshotStartOfMonth(containing date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}

private extension Array {
    func rotatedLeft(by distance: Int) -> [Element] {
        guard !isEmpty else { return [] }
        let offset = distance % count
        guard offset > 0 else { return self }
        return Array(self[offset...]) + Array(self[..<offset])
    }
}

extension MediaLibraryManager {
    private static func generatedArtwork(size: CGSize = CGSize(width: 300, height: 300), title: String, subtitle: String) -> MPMediaItemArtwork? {
        #if os(iOS)
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { ctx in
            // Background gradient
            let colors = [UIColor.systemPink.cgColor, UIColor.systemPurple.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])

            // Title text
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 36),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let textRect = CGRect(x: 12, y: size.height/2 - 24, width: size.width - 24, height: 48)
            (title as NSString).draw(in: textRect, withAttributes: attrs)
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in uiImage }
        #else
        return nil
        #endif
    }

    private static var isScreenshotModeEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotMode") ||
            ProcessInfo.processInfo.environment["PLAYCOUNT_SCREENSHOT_MODE"] == "1"
    }

    private func loadScreenshotFixture() {
        let songs = Self.screenshotSongs
        librarySongs = songs
        libraryAlbums = Self.screenshotAlbums(from: songs)
        libraryArtists = Self.screenshotArtists(from: songs)
        librarySummary = LibrarySummary(songs: librarySongs, albums: libraryAlbums, artists: libraryArtists)
        topSongs = Array(librarySongs.prefix(20))
        topAlbums = Array(libraryAlbums.prefix(20))
        topArtists = Array(libraryArtists.prefix(20))
        updateLibraryIndexes(songs: librarySongs, albums: libraryAlbums, artists: libraryArtists)
        monthlyRecap = Self.screenshotRecap(from: songs)
        availableRecapMonths = Self.screenshotRecapMonths(endingAt: monthlyRecap.monthStart)
        hasLoadedInitialSnapshot = true
        nowPlayingState = NowPlayingState(
            title: songs[0].title,
            subtitle: "\(songs[0].artist) — \(songs[0].albumTitle)",
            artwork: songs[0].artwork,
            duration: songs[0].playbackDuration,
            currentTime: 68,
            isPlaying: true,
            playCount: songs[0].playCount,
            song: songs[0]
        )
    }

    private static var screenshotSongs: [TopSong] {
        [
            screenshotSong(id: 101, title: "Afterglow Drive", artist: "Nova Lane", album: "Glass Coast", plays: 184, delta: 18, duration: 214, initials: "AD", colors: [.systemPink, .systemOrange], coverIndex: 1),
            screenshotSong(id: 102, title: "Velvet Static", artist: "Mira Vale", album: "Night Signal", plays: 161, delta: 16, duration: 198, initials: "VS", colors: [.systemPurple, .systemBlue], coverIndex: 2),
            screenshotSong(id: 103, title: "Golden Hour", artist: "The Satellites", album: "Solar Bloom", plays: 149, delta: 15, duration: 236, initials: "GH", colors: [.systemYellow, .systemTeal], coverIndex: 3),
            screenshotSong(id: 104, title: "North Star", artist: "Nova Lane", album: "Quiet Motion", plays: 132, delta: 14, duration: 221, initials: "NS", colors: [.systemIndigo, .systemMint], coverIndex: 4, artistID: 1_101),
            screenshotSong(id: 105, title: "Soft Focus", artist: "Vera June", album: "Dayglow Static", plays: 118, delta: 13, duration: 205, initials: "SF", colors: [.systemPurple, .systemBlue], coverIndex: 5),
            screenshotSong(id: 106, title: "City Lights", artist: "Juniper Park", album: "Late Checkout", plays: 104, delta: 12, duration: 187, initials: "CL", colors: [.systemRed, .systemBrown], coverIndex: 6),
            screenshotSong(id: 107, title: "Clear Water", artist: "Eli North", album: "Blue Room", plays: 93, delta: 11, duration: 203, initials: "CW", colors: [.systemCyan, .systemBlue], coverIndex: 7),
            screenshotSong(id: 108, title: "Paper Moon", artist: "Nova Lane", album: "Soft Geometry", plays: 88, delta: 10, duration: 192, initials: "PM", colors: [.systemOrange, .systemTeal], coverIndex: 8, artistID: 1_101),
            screenshotSong(id: 109, title: "Glass Rain", artist: "The Meridian", album: "Prism House", plays: 82, delta: 9, duration: 225, initials: "GR", colors: [.systemPink, .systemCyan], coverIndex: 9),
            screenshotSong(id: 110, title: "Low Tide", artist: "Cassia Row", album: "Silver Dunes", plays: 76, delta: 8, duration: 218, initials: "LT", colors: [.systemGray, .systemOrange], coverIndex: 10),
            screenshotSong(id: 111, title: "Electric Blue", artist: "Ocean Avenue", album: "Deep Signal", plays: 69, delta: 7, duration: 207, initials: "EB", colors: [.systemBlue, .systemMint], coverIndex: 11),
            screenshotSong(id: 112, title: "Red Planet", artist: "Noah Sol", album: "Painted Weather", plays: 61, delta: 6, duration: 201, initials: "RP", colors: [.systemRed, .systemOrange], coverIndex: 12)
        ]
    }

    private static func screenshotSong(
        id: UInt64,
        title: String,
        artist: String,
        album: String,
        plays: Int,
        delta: Int,
        duration: TimeInterval,
        initials: String,
        colors: [UIColor],
        coverIndex: Int,
        artistID: UInt64? = nil
    ) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: artist,
            albumTitle: album,
            playCount: plays,
            skipCount: max(0, delta / 4),
            totalPlayDuration: TimeInterval(plays) * duration,
            playbackDuration: duration,
            lastPlayedDate: Date().addingTimeInterval(-TimeInterval(id * 1200)),
            dateAdded: Date().addingTimeInterval(-TimeInterval(id * 3200)),
            artwork: screenshotArtwork(coverIndex: coverIndex, title: initials, subtitle: artist, colors: colors),
            albumPersistentID: id,
            artistPersistentID: artistID ?? id + 1_000,
            trackNumber: Int(id % 10)
        )
    }

    private static func screenshotArtwork(coverIndex: Int, title: String, subtitle: String, colors: [UIColor]) -> MPMediaItemArtwork? {
        let assetName = String(format: "PlayCountScreenshotCover%02d", coverIndex)
        if let image = UIImage(named: assetName) {
            return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }

        return generatedArtwork(title: title, subtitle: subtitle, colors: colors)
    }

    private static func generatedArtwork(
        size: CGSize = CGSize(width: 300, height: 300),
        title: String,
        subtitle: String,
        colors: [UIColor]
    ) -> MPMediaItemArtwork? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let uiImage = renderer.image { ctx in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors.map(\.cgColor) as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            UIColor.white.withAlphaComponent(0.18).setStroke()
            let inset = size.width * 0.15
            ctx.cgContext.setLineWidth(6)
            ctx.cgContext.strokeEllipse(in: CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2))

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.78),
                .paragraphStyle: paragraph
            ]
            (title as NSString).draw(in: CGRect(x: 16, y: 118, width: size.width - 32, height: 58), withAttributes: titleAttributes)
            (subtitle as NSString).draw(in: CGRect(x: 16, y: 174, width: size.width - 32, height: 28), withAttributes: subtitleAttributes)
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in uiImage }
    }

    private static func screenshotAlbums(from songs: [TopSong]) -> [TopAlbum] {
        let grouped = Dictionary(grouping: songs, by: \.albumTitle)
        return grouped.map { albumTitle, songs in
            let first = songs[0]
            return TopAlbum(
                id: first.albumPersistentID,
                title: albumTitle,
                artist: first.artist,
                playCount: songs.reduce(0) { $0 + $1.playCount },
                totalPlayDuration: songs.reduce(0) { $0 + $1.totalPlayDuration },
                artwork: first.artwork,
                artistPersistentID: first.artistPersistentID
            )
        }
        .sorted { $0.playCount > $1.playCount }
    }

    private static func screenshotArtists(from songs: [TopSong]) -> [TopArtist] {
        let grouped = Dictionary(grouping: songs, by: \.artist)
        return grouped.map { artist, songs in
            let first = songs[0]
            return TopArtist(
                id: first.artistPersistentID,
                name: artist,
                playCount: songs.reduce(0) { $0 + $1.playCount },
                totalPlayDuration: songs.reduce(0) { $0 + $1.totalPlayDuration },
                artwork: first.artwork
            )
        }
        .sorted { $0.playCount > $1.playCount }
    }

    private static func screenshotRecap(from songs: [TopSong], monthStart overrideMonthStart: Date? = nil) -> MonthlyRecap {
        let calendar = Calendar.current
        let monthStart = overrideMonthStart.map { calendar.screenshotStartOfMonth(containing: $0) }
            ?? calendar.screenshotStartOfMonth(containing: Date())
        let monthOrdinal = calendar.component(.year, from: monthStart) * 12 + calendar.component(.month, from: monthStart)
        let rotation = abs(monthOrdinal) % max(songs.count, 1)
        let monthlySongs = songs.rotatedLeft(by: rotation)
        let monthlyDeltas = [46, 39, 35, 31, 27, 24, 21, 18, 15, 13, 11, 9]
            .map { max(4, $0 - (abs(monthOrdinal) % 4) * 2) }

        let rankedSongs = zip(monthlySongs, monthlyDeltas).map { song, delta in
            MonthlyRecap.RankedSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                albumTitle: song.albumTitle,
                playDelta: delta,
                skipDelta: max(0, delta / 5),
                listeningDuration: TimeInterval(delta) * song.playbackDuration,
                artwork: song.artwork
            )
        }

        let albums = screenshotAlbums(from: monthlySongs).map { album in
            MonthlyRecap.RankedGroup(
                id: String(album.id),
                title: album.title,
                subtitle: album.artist,
                playDelta: max(6, album.playCount / 18),
                listeningDuration: album.totalPlayDuration / 18,
                artwork: album.artwork
            )
        }

        let artists = screenshotArtists(from: monthlySongs).map { artist in
            MonthlyRecap.RankedGroup(
                id: String(artist.id),
                title: artist.name,
                subtitle: "Artist",
                playDelta: max(7, artist.playCount / 20),
                listeningDuration: artist.totalPlayDuration / 20,
                artwork: artist.artwork
            )
        }

        let trackingStart = calendar.date(byAdding: .month, value: -4, to: monthStart) ?? Date().addingTimeInterval(-60 * 60 * 24 * 120)

        return MonthlyRecap(
            monthStart: monthStart,
            generatedAt: Date(),
            lastCaptureReason: .manualRefresh,
            trackingStart: trackingStart,
            snapshotCount: 58,
            totalPlayDelta: monthlyDeltas.reduce(0, +),
            totalSkipDelta: 19,
            totalListeningDuration: rankedSongs.reduce(0) { $0 + $1.listeningDuration },
            playedSongCount: rankedSongs.count,
            newSongCount: 7,
            topSongs: rankedSongs,
            topArtists: Array(artists),
            topAlbums: Array(albums),
            biggestGainers: [
                MonthlyRecap.MovementSong(id: monthlySongs[2].id, title: monthlySongs[2].title, artist: monthlySongs[2].artist, playDelta: monthlyDeltas[2], rankChange: 42, currentRank: 12, previousRank: 54, artwork: monthlySongs[2].artwork),
                MonthlyRecap.MovementSong(id: monthlySongs[4].id, title: monthlySongs[4].title, artist: monthlySongs[4].artist, playDelta: monthlyDeltas[4], rankChange: 31, currentRank: 18, previousRank: 49, artwork: monthlySongs[4].artwork),
                MonthlyRecap.MovementSong(id: monthlySongs[6].id, title: monthlySongs[6].title, artist: monthlySongs[6].artist, playDelta: monthlyDeltas[6], rankChange: 24, currentRank: 21, previousRank: 45, artwork: monthlySongs[6].artwork),
                MonthlyRecap.MovementSong(id: monthlySongs[8].id, title: monthlySongs[8].title, artist: monthlySongs[8].artist, playDelta: monthlyDeltas[8], rankChange: 18, currentRank: 29, previousRank: 47, artwork: monthlySongs[8].artwork)
            ],
            topNewSongs: Array(rankedSongs.suffix(7))
        )
    }

    private static func screenshotRecapMonths(endingAt monthStart: Date) -> [Date] {
        let calendar = Calendar.current
        let currentMonth = calendar.screenshotStartOfMonth(containing: monthStart)
        return (0...17).compactMap {
            calendar.date(byAdding: .month, value: -17 + $0, to: currentMonth)
        }
    }

    static var previewPlaying: MediaLibraryManager {
        let manager = MediaLibraryManager(fetchLimit: 0)
        let sampleSong = TopSong(
            id: 1,
            title: "Midnight City",
            artist: "M83",
            albumTitle: "Hurry Up, We're Dreaming",
            playCount: 42,
            skipCount: 3,
            totalPlayDuration: TimeInterval(240 * 42),
            playbackDuration: 240,
            lastPlayedDate: nil,
            dateAdded: nil,
            artwork: generatedArtwork(title: "MC", subtitle: "M83"),
            albumPersistentID: 1,
            artistPersistentID: 1,
            trackNumber: 1
        )

        manager.nowPlayingState = NowPlayingState(
            title: sampleSong.title,
            subtitle: "\(sampleSong.artist) — \(sampleSong.albumTitle)",
            artwork: sampleSong.artwork,
            duration: 240,
            currentTime: 87,
            isPlaying: true,
            playCount: sampleSong.playCount,
            song: sampleSong
        )
        return manager
    }

    static var previewPaused: MediaLibraryManager {
        let manager = MediaLibraryManager(fetchLimit: 0)
        let sampleSong = TopSong(
            id: 2,
            title: "Holocene",
            artist: "Bon Iver",
            albumTitle: "Bon Iver",
            playCount: 17,
            skipCount: 1,
            totalPlayDuration: TimeInterval(302 * 17),
            playbackDuration: 302,
            lastPlayedDate: nil,
            dateAdded: nil,
            artwork: generatedArtwork(title: "H", subtitle: "BI"),
            albumPersistentID: 2,
            artistPersistentID: 2,
            trackNumber: 2
        )

        manager.nowPlayingState = NowPlayingState(
            title: sampleSong.title,
            subtitle: "\(sampleSong.artist) — \(sampleSong.albumTitle)",
            artwork: sampleSong.artwork,
            duration: 302,
            currentTime: 0,
            isPlaying: false,
            playCount: sampleSong.playCount,
            song: sampleSong
        )
        return manager
    }
}
#endif
