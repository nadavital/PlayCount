import Foundation
import Combine
@preconcurrency import MediaPlayer
import AppIntents

struct TopSong: Identifiable {
    let id: UInt64
    let title: String
    let artist: String
    let albumTitle: String
    let playCount: Int
    let totalPlayDuration: TimeInterval
    let lastPlayedDate: Date?
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

final class MediaLibraryManager: ObservableObject, Sendable {
    
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
                return duration.formattedPlayback
            }
        }

        func supplementaryDescription(playCount: Int, duration: TimeInterval) -> String {
            switch self {
            case .playCount:
                return "\(duration.formattedPlayback) listened"
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
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var sortMetric: SortMetric = .playCount {
        didSet {
            applySortAndLimit()
        }
    }
    @Published private(set) var hasLoadedInitialSnapshot = false
    @Published private(set) var nowPlayingState: NowPlayingState?

    private let fetchLimit: Int
    private let musicPlayer = MPMusicPlayerController.systemMusicPlayer
    private var notificationObservers: [NSObjectProtocol] = []
    private var progressTimer: AnyCancellable?

    init(fetchLimit: Int = 20) {
        self.fetchLimit = fetchLimit
        authorizationStatus = MPMediaLibrary.authorizationStatus()

        musicPlayer.beginGeneratingPlaybackNotifications()
        configureNowPlayingObservers()
        updateNowPlayingState()

        if authorizationStatus == .authorized {
            refreshTopItems()
        }
    }

    deinit {
        teardownNowPlayingObservers()
        musicPlayer.endGeneratingPlaybackNotifications()
    }

    func requestAuthorizationIfNeeded() {
        switch authorizationStatus {
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
        default:
            break
        }
    }

    func refreshTopItems() {
        guard authorizationStatus == .authorized else { return }

        isLoading = true
        errorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let songs = Self.fetchTopSongs()
            let albums = Self.fetchTopAlbums()
            let artists = Self.fetchTopArtists()

            DispatchQueue.main.async {
                self.librarySongs = songs
                self.libraryAlbums = albums
                self.libraryArtists = artists

                self.applySortAndLimit()
                self.isLoading = false
                self.hasLoadedInitialSnapshot = true

                if songs.isEmpty && albums.isEmpty && artists.isEmpty {
                    self.errorMessage = "We couldn't find any listening data in your media library."
                }
            }
        }
    }

    private func applySortAndLimit() {
        topSongs = Array(sortSongs(librarySongs).prefix(fetchLimit))
        topAlbums = Array(sortAlbums(libraryAlbums).prefix(fetchLimit))
        topArtists = Array(sortArtists(libraryArtists).prefix(fetchLimit))
    }

    func songs(for album: TopAlbum, limit: Int? = nil) -> [TopSong] {
        let filtered = librarySongs.filter { song in
            if album.id != 0, song.albumPersistentID == album.id {
                return true
            }

            let sameTitle = song.albumTitle.localizedCaseInsensitiveCompare(album.title) == .orderedSame
            let sameArtistID = album.artistPersistentID != 0 && song.artistPersistentID == album.artistPersistentID
            let sameArtistName = song.artist.localizedCaseInsensitiveCompare(album.artist) == .orderedSame

            if song.albumPersistentID == 0 && sameTitle && (sameArtistID || sameArtistName) {
                return true
            }

            return false
        }

        let sorted = sortSongs(filtered)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func songs(for artist: TopArtist, limit: Int? = nil) -> [TopSong] {
        let filtered = librarySongs.filter { song in
            if artist.id != 0, song.artistPersistentID == artist.id {
                return true
            }

            if song.artistPersistentID == 0 {
                return song.artist.localizedCaseInsensitiveCompare(artist.name) == .orderedSame
            }

            return false
        }

        let sorted = sortSongs(filtered)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func albums(for artist: TopArtist, limit: Int? = nil) -> [TopAlbum] {
        let filtered = libraryAlbums.filter { album in
            if artist.id != 0, album.artistPersistentID == artist.id {
                return true
            }

            return album.artist.localizedCaseInsensitiveCompare(artist.name) == .orderedSame
        }

        let sorted = sortAlbums(filtered)
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func album(withPersistentID id: UInt64) -> TopAlbum? {
        if let match = topAlbums.first(where: { $0.id == id }) {
            return match
        }

        return libraryAlbums.first(where: { $0.id == id })
    }

    func artist(withPersistentID id: UInt64) -> TopArtist? {
        if let match = topArtists.first(where: { $0.id == id }) {
            return match
        }

        return libraryArtists.first(where: { $0.id == id })
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
        updateNowPlayingState()
    }

    private func sortSongs(_ songs: [TopSong]) -> [TopSong] {
        songs.sorted { lhs, rhs in
            switch sortMetric {
            case .playCount:
                if lhs.playCount == rhs.playCount {
                    if lhs.totalPlayDuration == rhs.totalPlayDuration {
                        return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
                    }
                    return lhs.totalPlayDuration > rhs.totalPlayDuration
                }
                return lhs.playCount > rhs.playCount
            case .listenTime:
                if lhs.totalPlayDuration == rhs.totalPlayDuration {
                    if lhs.playCount == rhs.playCount {
                        return (lhs.lastPlayedDate ?? .distantPast) > (rhs.lastPlayedDate ?? .distantPast)
                    }
                    return lhs.playCount > rhs.playCount
                }
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
        }
    }

    private func configureNowPlayingObservers() {
        let center = NotificationCenter.default

        let itemObserver = center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: musicPlayer, queue: .main) { [weak self] _ in
            self?.handleNowPlayingChange()
        }

        let playbackObserver = center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: musicPlayer, queue: .main) { [weak self] _ in
            self?.handlePlaybackStateChange()
        }

        notificationObservers = [itemObserver, playbackObserver]
    }

    private func teardownNowPlayingObservers() {
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
    }

    private func handlePlaybackStateChange() {
        updateNowPlayingState()

        switch musicPlayer.playbackState {
        case .playing:
            startProgressUpdates()
        default:
            stopProgressUpdates()
        }
    }

    private func startProgressUpdates() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateNowPlayingState()
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
            totalPlayDuration: totalPlayDuration,
            lastPlayedDate: item.lastPlayedDate,
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

    private func sortAlbums(_ albums: [TopAlbum]) -> [TopAlbum] {
        albums.sorted { lhs, rhs in
            switch sortMetric {
            case .playCount:
                if lhs.playCount == rhs.playCount {
                    if lhs.totalPlayDuration == rhs.totalPlayDuration {
                        return lhs.title < rhs.title
                    }
                    return lhs.totalPlayDuration > rhs.totalPlayDuration
                }
                return lhs.playCount > rhs.playCount
            case .listenTime:
                if lhs.totalPlayDuration == rhs.totalPlayDuration {
                    if lhs.playCount == rhs.playCount {
                        return lhs.title < rhs.title
                    }
                    return lhs.playCount > rhs.playCount
                }
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
        }
    }

    private func sortArtists(_ artists: [TopArtist]) -> [TopArtist] {
        artists.sorted { lhs, rhs in
            switch sortMetric {
            case .playCount:
                if lhs.playCount == rhs.playCount {
                    if lhs.totalPlayDuration == rhs.totalPlayDuration {
                        return lhs.name < rhs.name
                    }
                    return lhs.totalPlayDuration > rhs.totalPlayDuration
                }
                return lhs.playCount > rhs.playCount
            case .listenTime:
                if lhs.totalPlayDuration == rhs.totalPlayDuration {
                    if lhs.playCount == rhs.playCount {
                        return lhs.name < rhs.name
                    }
                    return lhs.playCount > rhs.playCount
                }
                return lhs.totalPlayDuration > rhs.totalPlayDuration
            }
        }
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
                    totalPlayDuration: totalDuration,
                    lastPlayedDate: item.lastPlayedDate,
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

    static var previewPlaying: MediaLibraryManager {
        let manager = MediaLibraryManager(fetchLimit: 0)
        let sampleSong = TopSong(
            id: 1,
            title: "Midnight City",
            artist: "M83",
            albumTitle: "Hurry Up, We're Dreaming",
            playCount: 42,
            totalPlayDuration: TimeInterval(240 * 42),
            lastPlayedDate: nil,
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
            totalPlayDuration: TimeInterval(302 * 17),
            lastPlayedDate: nil,
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
