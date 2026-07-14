import AppIntents
import Foundation
@preconcurrency import MediaPlayer
import SwiftUI

enum PlayCountIntentError: LocalizedError, Sendable {
    case mediaLibraryPermissionRequired
    case emptyLibrary
    case songNotFound
    case albumNotFound
    case artistNotFound
    case nothingPlaying
    case recapUnavailable

    var errorDescription: String? {
        switch self {
        case .mediaLibraryPermissionRequired:
            return String(localized: "Allow PlayCount to access your media library in Settings, then try again.")
        case .emptyLibrary:
            return String(localized: "PlayCount couldn't find any songs with listening data in your library.")
        case .songNotFound:
            return String(localized: "PlayCount couldn't find that song in your library.")
        case .albumNotFound:
            return String(localized: "PlayCount couldn't find that album in your library.")
        case .artistNotFound:
            return String(localized: "PlayCount couldn't find that artist in your library.")
        case .nothingPlaying:
            return String(localized: "There isn't a song playing right now.")
        case .recapUnavailable:
            return String(localized: "PlayCount doesn't have enough snapshot history for that recap yet.")
        }
    }
}

struct PlayCountIntentLibrarySnapshot {
    let songs: [TopSong]
    let albums: [TopAlbum]
    let artists: [TopArtist]
}

final class PlayCountIntentLibraryCache: @unchecked Sendable {
    static let shared = PlayCountIntentLibraryCache()

    private let lock = NSLock()
    private let lifetime: TimeInterval
    private let loader: @Sendable () -> PlayCountIntentLibrarySnapshot
    private var cached: (date: Date, snapshot: PlayCountIntentLibrarySnapshot)?

    init(
        lifetime: TimeInterval = 5,
        loader: @escaping @Sendable () -> PlayCountIntentLibrarySnapshot = {
            let snapshot = MediaLibraryManager.intentLibrarySnapshot()
            return PlayCountIntentLibrarySnapshot(
                songs: snapshot.songs,
                albums: snapshot.albums,
                artists: snapshot.artists
            )
        }
    ) {
        self.lifetime = lifetime
        self.loader = loader
    }

    func snapshot(now: Date = Date()) -> PlayCountIntentLibrarySnapshot {
        lock.lock()
        defer { lock.unlock() }
        if let cached, now.timeIntervalSince(cached.date) < lifetime {
            return cached.snapshot
        }
        let snapshot = loader()
        cached = (now, snapshot)
        return snapshot
    }

    func invalidate() {
        lock.withLock { cached = nil }
    }
}

struct PlayCountIntentLibrary: Sendable {
    private let cache: PlayCountIntentLibraryCache

    init(cache: PlayCountIntentLibraryCache = .shared) {
        self.cache = cache
    }

    func songs() throws -> [TopSong] {
        try requireAuthorization()
        let songs = cache.snapshot().songs
        guard !songs.isEmpty else { throw PlayCountIntentError.emptyLibrary }
        return songs
    }

    func albums() throws -> [TopAlbum] {
        try requireAuthorization()
        let albums = cache.snapshot().albums
        guard !albums.isEmpty else { throw PlayCountIntentError.emptyLibrary }
        return albums
    }

    func artists() throws -> [TopArtist] {
        try requireAuthorization()
        let artists = cache.snapshot().artists
        guard !artists.isEmpty else { throw PlayCountIntentError.emptyLibrary }
        return artists
    }

    func nowPlayingSong() throws -> TopSong {
        try requireAuthorization()
        guard let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem,
              item.persistentID != 0 else {
            throw PlayCountIntentError.nothingPlaying
        }

        if let song = try songs().first(where: { $0.id == item.persistentID }) {
            return song
        }
        throw PlayCountIntentError.songNotFound
    }

    private func requireAuthorization() throws {
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            cache.invalidate()
            throw PlayCountIntentError.mediaLibraryPermissionRequired
        }
    }
}

struct SongEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Song")
    static let defaultQuery = SongEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Artist")
    var artist: String

    @Property(title: "Album")
    var album: String

    @Property(title: "Play Count")
    var playCount: Int

    @Property(title: "Listening Time")
    var listeningTime: TimeInterval

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(artist)",
            image: .init(systemName: "music.note")
        )
    }

    init(song: TopSong) {
        id = String(song.id)
        title = song.title
        artist = song.artist
        album = song.albumTitle
        playCount = song.playCount
        listeningTime = song.totalPlayDuration
    }
}

struct AlbumEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Album")
    static let defaultQuery = AlbumEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Artist")
    var artist: String

    @Property(title: "Play Count")
    var playCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artist)", image: .init(systemName: "square.stack"))
    }

    init(album: TopAlbum) {
        id = String(album.id)
        title = album.title
        artist = album.artist
        playCount = album.playCount
    }
}

struct ArtistEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Artist")
    static let defaultQuery = ArtistEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    @Property(title: "Play Count")
    var playCount: Int

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "music.mic"))
    }

    init(artist: TopArtist) {
        id = String(artist.id)
        name = artist.name
        playCount = artist.playCount
    }
}

struct SongEntityQuery: EntityStringQuery, EnumerableEntityQuery {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    private let library = PlayCountIntentLibrary()

    func entities(for identifiers: [SongEntity.ID]) async throws -> [SongEntity] {
        let requested = Set(identifiers.compactMap(UInt64.init))
        return try library.songs().filter { requested.contains($0.id) }.map(SongEntity.init)
    }

    func entities(matching string: String) async throws -> [SongEntity] {
        try PlayCountIntentRanking.matchingSongs(library.songs(), search: string).map(SongEntity.init)
    }

    func suggestedEntities() async throws -> [SongEntity] {
        try library.songs().sorted(by: Self.songOrder).prefix(20).map(SongEntity.init)
    }

    func allEntities() async throws -> [SongEntity] {
        try library.songs().map(SongEntity.init)
    }

    private static func songOrder(_ lhs: TopSong, _ rhs: TopSong) -> Bool {
        if lhs.playCount == rhs.playCount { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return lhs.playCount > rhs.playCount
    }
}

struct AlbumEntityQuery: EntityStringQuery {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    private let library = PlayCountIntentLibrary()

    func entities(for identifiers: [AlbumEntity.ID]) async throws -> [AlbumEntity] {
        let requested = Set(identifiers.compactMap(UInt64.init))
        return try library.albums().filter { requested.contains($0.id) }.map(AlbumEntity.init)
    }

    func entities(matching string: String) async throws -> [AlbumEntity] {
        try library.albums()
            .filter { $0.title.localizedStandardContains(string) || $0.artist.localizedStandardContains(string) }
            .sorted { $0.playCount > $1.playCount }
            .prefix(25)
            .map(AlbumEntity.init)
    }

    func suggestedEntities() async throws -> [AlbumEntity] {
        try library.albums().sorted { $0.playCount > $1.playCount }.prefix(20).map(AlbumEntity.init)
    }
}

struct ArtistEntityQuery: EntityStringQuery {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    private let library = PlayCountIntentLibrary()

    func entities(for identifiers: [ArtistEntity.ID]) async throws -> [ArtistEntity] {
        let requested = Set(identifiers.compactMap(UInt64.init))
        return try library.artists().filter { requested.contains($0.id) }.map(ArtistEntity.init)
    }

    func entities(matching string: String) async throws -> [ArtistEntity] {
        try library.artists()
            .filter { $0.name.localizedStandardContains(string) }
            .sorted { $0.playCount > $1.playCount }
            .prefix(25)
            .map(ArtistEntity.init)
    }

    func suggestedEntities() async throws -> [ArtistEntity] {
        try library.artists().sorted { $0.playCount > $1.playCount }.prefix(20).map(ArtistEntity.init)
    }
}

enum RankingMetric: String, AppEnum {
    case plays
    case listeningTime

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ranking Metric")
    static let caseDisplayRepresentations: [RankingMetric: DisplayRepresentation] = [
        .plays: "Plays",
        .listeningTime: "Listening Time"
    ]
}

enum PlayCountIntentRanking {
    static func topSongs(from songs: [TopSong], metric: RankingMetric, limit: Int) -> [TopSong] {
        let safeLimit = max(0, limit)
        return Array(songs.sorted {
            switch metric {
            case .plays:
                return $0.playCount == $1.playCount
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.playCount > $1.playCount
            case .listeningTime:
                return $0.totalPlayDuration == $1.totalPlayDuration
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.totalPlayDuration > $1.totalPlayDuration
            }
        }.prefix(safeLimit))
    }

    static func matchingSongs(_ songs: [TopSong], search: String, limit: Int = 25) -> [TopSong] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return topSongs(from: songs, metric: .plays, limit: limit) }
        return topSongs(
            from: songs.filter {
                $0.title.localizedStandardContains(query) ||
                    $0.artist.localizedStandardContains(query) ||
                    $0.albumTitle.localizedStandardContains(query)
            },
            metric: .plays,
            limit: limit
        )
    }
}

struct TopSongsIntent: AppIntent {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let title: LocalizedStringResource = "Get Top Songs"
    static let description = IntentDescription("Gets your highest-ranked songs from your media library.", categoryName: "Listening Stats")

    @Parameter(title: "Number of Songs", default: 5, inclusiveRange: (1, 20))
    var limit: Int

    @Parameter(title: "Rank By", default: .plays)
    var metric: RankingMetric

    static var parameterSummary: some ParameterSummary {
        Summary("Get the top \(\.$limit) songs by \(\.$metric)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[SongEntity]> & ProvidesDialog & ShowsSnippetView {
        let songs = try PlayCountIntentLibrary().songs()
        let entities = PlayCountIntentRanking.topSongs(from: songs, metric: metric, limit: limit).map(SongEntity.init)
        let names = entities.map(\.title).formatted()
        return .result(value: entities, dialog: "Your top songs are \(names).", view: TopSongsSnippet(songs: entities, metric: metric))
    }
}

struct SongPlayCountIntent: AppIntent {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let title: LocalizedStringResource = "Get Song Play Count"
    static let description = IntentDescription("Gets the number of times you have played a song.", categoryName: "Listening Stats")

    @Parameter(title: "Song", requestValueDialog: "Which song?")
    var song: SongEntity

    static var parameterSummary: some ParameterSummary { Summary("Get the play count for \(\.$song)") }

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog & ShowsSnippetView {
        guard let resolved = try await SongEntityQuery().entities(for: [song.id]).first else {
            throw PlayCountIntentError.songNotFound
        }
        return .result(value: resolved.playCount, dialog: "You have played \(resolved.title) by \(resolved.artist) \(resolved.playCount) times.", view: SongStatsSnippet(song: resolved))
    }
}

struct CurrentSongStatsIntent: AppIntent {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let title: LocalizedStringResource = "Get Current Song Stats"
    static let description = IntentDescription("Gets listening statistics for the song currently playing.", categoryName: "Listening Stats")

    func perform() async throws -> some IntentResult & ReturnsValue<SongEntity> & ProvidesDialog & ShowsSnippetView {
        let entity = SongEntity(song: try PlayCountIntentLibrary().nowPlayingSong())
        return .result(value: entity, dialog: "You have played \(entity.title) \(entity.playCount) times.", view: SongStatsSnippet(song: entity))
    }
}

struct LatestRecapIntent: AppIntent {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let title: LocalizedStringResource = "Get Latest Recap"
    static let description = IntentDescription("Summarizes your latest PlayCount listening recap.", categoryName: "Recaps")

    @Dependency private var manager: MediaLibraryManager

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let recap = PlayCountIntentRecaps.latestUsable(
            from: [manager.monthlyRecap] + manager.recaps(forMonthsContaining: manager.availableRecapMonths)
        ) else {
            throw PlayCountIntentError.recapUnavailable
        }
        guard recap.totalPlayDelta > 0, let topSong = recap.topSongs.first else {
            throw PlayCountIntentError.recapUnavailable
        }
        let month = recap.monthStart.formatted(.dateTime.month(.wide).year())
        let summary = "\(month): \(recap.totalPlayDelta) plays. Your top song was \(topSong.title) by \(topSong.artist) with \(topSong.playDelta) plays."
        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

struct BiggestGainerIntent: AppIntent {
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    static let title: LocalizedStringResource = "Get Biggest Gainer"
    static let description = IntentDescription("Gets the song that climbed the most in your latest recap.", categoryName: "Recaps")

    @Dependency private var manager: MediaLibraryManager

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let recap = PlayCountIntentRecaps.latestUsable(
            from: [manager.monthlyRecap] + manager.recaps(forMonthsContaining: manager.availableRecapMonths)
        ), let song = recap.biggestGainers.first else {
            throw PlayCountIntentError.recapUnavailable
        }
        let response = "\(song.title) by \(song.artist) climbed \(song.rankChange) places in your latest recap."
        return .result(value: response, dialog: IntentDialog(stringLiteral: response))
    }
}

enum PlayCountIntentRecaps {
    static func latestUsable(from recaps: [MonthlyRecap]) -> MonthlyRecap? {
        recaps
            .filter(\.hasActivity)
            .max { $0.monthStart < $1.monthStart }
    }
}

struct TopSongsThisMonthIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Top Songs This Month"
    static let description = IntentDescription("Gets the songs with the most new plays in your latest monthly recap.", categoryName: "Recaps")

    @Parameter(title: "Number of Songs", default: 5, inclusiveRange: (1, 10))
    var limit: Int

    @Dependency private var manager: MediaLibraryManager

    static var parameterSummary: some ParameterSummary { Summary("Get the top \(\.$limit) songs this month") }

    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        guard let recap = PlayCountIntentRecaps.latestUsable(
            from: [manager.monthlyRecap] + manager.recaps(forMonthsContaining: manager.availableRecapMonths)
        ) else {
            throw PlayCountIntentError.recapUnavailable
        }
        let songs = Array(recap.topSongs.prefix(limit))
        guard !songs.isEmpty else { throw PlayCountIntentError.recapUnavailable }
        let titles = songs.map { "\($0.title) by \($0.artist)" }
        return .result(value: titles, dialog: "Your top songs this month are \(titles.formatted()).")
    }
}

struct TopArtistThisYearIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Top Artist This Year"
    static let description = IntentDescription("Gets your most-played artist in this year's PlayCount recaps.", categoryName: "Recaps")

    @Dependency private var manager: MediaLibraryManager

    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let year = Calendar.current.component(.year, from: Date())
        guard let artist = manager.yearlyRecap(for: year).topArtists.first else {
            throw PlayCountIntentError.recapUnavailable
        }
        let response = "Your top artist of \(year) is \(artist.title), with \(artist.playDelta) plays."
        return .result(value: artist.title, dialog: IntentDialog(stringLiteral: response))
    }
}

struct OpenLatestRecapIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Latest Recap"
    static let description = IntentDescription("Opens your latest listening recap in PlayCount.", categoryName: "Recaps")
    static let openAppWhenRun = true

    @Dependency private var manager: MediaLibraryManager

    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult {
        guard let recap = PlayCountIntentRecaps.latestUsable(
            from: [manager.monthlyRecap] + manager.recaps(forMonthsContaining: manager.availableRecapMonths)
        ) else {
            throw PlayCountIntentError.recapUnavailable
        }
        await MainActor.run {
            PlayCountNavigationRequestStore.requestLatestRecap(monthStart: recap.monthStart)
            NotificationCenter.default.post(name: .openMonthlyRecap, object: nil)
        }
        return .result()
    }
}

private struct TopSongsSnippet: View {
    let songs: [SongEntity]
    let metric: RankingMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                HStack(spacing: 10) {
                    Text(index + 1, format: .number).font(.headline).monospacedDigit()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title).font(.headline).lineLimit(1)
                        Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(metric == .plays ? "\(song.playCount)" : song.listeningTime.formattedListeningMinutes)
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
        }
        .padding()
    }
}

private struct SongStatsSnippet: View {
    let song: SongEntity

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note").font(.title2).frame(width: 44, height: 44).background(.quaternary, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.headline).lineLimit(1)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(song.playCount, format: .number).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .padding()
    }
}
