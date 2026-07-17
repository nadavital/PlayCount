import AppIntents
import CoreSpotlight
import Foundation
@preconcurrency import MediaPlayer
import SwiftUI

struct PlayCountSearchIndexStatus: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case notRun
        case ready
        case failed(String)
    }

    let state: State
    let lastUpdated: Date?
    let songCount: Int
    let albumCount: Int
    let artistCount: Int
}

enum PlayCountSiriIntegration {
    private static let searchIndexer = PlayCountSearchIndexer()

    static func updateSearchIndex(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist]
    ) async {
        await searchIndexer.update(songs: songs, albums: albums, artists: artists)
    }

    static func purgeSearchIndex() async {
        await searchIndexer.purge()
        if #available(iOS 27.0, *) {
            await updateNowPlayingRelevance(song: nil)
        }
    }

    static func searchIndexStatus() async -> PlayCountSearchIndexStatus {
        await searchIndexer.status()
    }

    static func rebuildSearchIndex(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist]
    ) async -> PlayCountSearchIndexStatus {
        await searchIndexer.rebuild(songs: songs, albums: albums, artists: artists)
    }

    @available(iOS 27.0, *)
    static func updateNowPlayingRelevance(song: TopSong?) async {
        do {
            if let song {
                try await RelevantEntities.shared.updateEntities(
                    [SiriAISongEntity(song: song)],
                    for: .audio(.nowPlaying)
                )
            } else {
                try await RelevantEntities.shared.removeAllEntities(for: .audio(.nowPlaying))
            }
        } catch {
            // Relevance donation is opportunistic and should not affect playback.
        }
    }
}

extension View {
    @ViewBuilder
    func playCountSongEntityIdentifier(_ song: TopSong) -> some View {
        if #available(iOS 27.0, *) {
            appEntityIdentifier(EntityIdentifier(for: SiriAISongEntity(song: song)))
        } else {
            appEntityIdentifier(EntityIdentifier(for: SongEntity(song: song)))
        }
    }

    @ViewBuilder
    func playCountAlbumEntityIdentifier(_ album: TopAlbum) -> some View {
        if #available(iOS 27.0, *) {
            appEntityIdentifier(EntityIdentifier(for: SiriAIAlbumEntity(album: album)))
        } else {
            appEntityIdentifier(EntityIdentifier(for: AlbumEntity(album: album)))
        }
    }

    @ViewBuilder
    func playCountArtistEntityIdentifier(_ artist: TopArtist) -> some View {
        if #available(iOS 27.0, *) {
            appEntityIdentifier(EntityIdentifier(for: SiriAIArtistEntity(artist: artist)))
        } else {
            appEntityIdentifier(EntityIdentifier(for: ArtistEntity(artist: artist)))
        }
    }
}

private actor PlayCountSearchIndexer {
    private let maximumIndexedSongs = 250
    private let maximumIndexedAlbums = 100
    private let maximumIndexedArtists = 100
    private var lastFingerprint: String?
    private var mutationTail: Task<Void, Never>?
    private var latestMutationID = 0
    private var lastStatus = PlayCountSearchIndexStatus(
        state: .notRun,
        lastUpdated: nil,
        songCount: 0,
        albumCount: 0,
        artistCount: 0
    )

    func update(songs: [TopSong], albums: [TopAlbum], artists: [TopArtist]) async {
        let fingerprint = PlayCountSearchFingerprint.make(songs: songs, albums: albums, artists: artists)
        guard fingerprint != lastFingerprint else { return }
        await enqueue(
            .update(
                songs: songs,
                albums: albums,
                artists: artists,
                fingerprint: fingerprint
            )
        )
    }

    private enum Mutation {
        case update(songs: [TopSong], albums: [TopAlbum], artists: [TopArtist], fingerprint: String)
        case purge
    }

    private func enqueue(_ mutation: Mutation) async {
        let predecessor = mutationTail
        latestMutationID &+= 1
        let mutationID = latestMutationID
        let task = Task { [weak self] in
            await predecessor?.value
            guard let self else { return }
            await self.perform(mutation)
        }
        mutationTail = task
        await task.value
        if latestMutationID == mutationID {
            mutationTail = nil
        }
    }

    private func perform(_ mutation: Mutation) async {
        switch mutation {
        case let .update(songs, albums, artists, fingerprint):
            await performUpdate(songs: songs, albums: albums, artists: artists, fingerprint: fingerprint)
        case .purge:
            await performPurge()
        }
    }

    private func performUpdate(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist],
        fingerprint: String
    ) async {
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
            await performPurge()
            return
        }
        lastFingerprint = nil
        let index = CSSearchableIndex.default()

        do {
            try await index.deleteAppEntities(ofType: SongEntity.self)
            try await index.deleteAppEntities(ofType: AlbumEntity.self)
            try await index.deleteAppEntities(ofType: ArtistEntity.self)

            if #available(iOS 27.0, *) {
                try await index.deleteAppEntities(ofType: SiriAISongEntity.self)
                try await index.deleteAppEntities(ofType: SiriAIAlbumEntity.self)
                try await index.deleteAppEntities(ofType: SiriAIArtistEntity.self)
                try await index.indexAppEntities(Array(songs.prefix(maximumIndexedSongs)).map(SiriAISongEntity.init), priority: 2)
                try await index.indexAppEntities(Array(albums.prefix(maximumIndexedAlbums)).map(SiriAIAlbumEntity.init))
                try await index.indexAppEntities(Array(artists.prefix(maximumIndexedArtists)).map(SiriAIArtistEntity.init))
            } else {
                try await index.indexAppEntities(Array(songs.prefix(maximumIndexedSongs)).map(SongEntity.init), priority: 1)
                try await index.indexAppEntities(Array(albums.prefix(maximumIndexedAlbums)).map(AlbumEntity.init))
                try await index.indexAppEntities(Array(artists.prefix(maximumIndexedArtists)).map(ArtistEntity.init))
            }
            guard MPMediaLibrary.authorizationStatus() == .authorized else {
                await performPurge()
                return
            }
            lastFingerprint = fingerprint
            lastStatus = PlayCountSearchIndexStatus(
                state: .ready,
                lastUpdated: Date(),
                songCount: min(songs.count, maximumIndexedSongs),
                albumCount: min(albums.count, maximumIndexedAlbums),
                artistCount: min(artists.count, maximumIndexedArtists)
            )
        } catch {
            lastStatus = PlayCountSearchIndexStatus(
                state: .failed(error.localizedDescription),
                lastUpdated: Date(),
                songCount: 0,
                albumCount: 0,
                artistCount: 0
            )
        }
    }

    func rebuild(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist]
    ) async -> PlayCountSearchIndexStatus {
        let fingerprint = PlayCountSearchFingerprint.make(songs: songs, albums: albums, artists: artists)
        lastFingerprint = nil
        await enqueue(
            .update(
                songs: songs,
                albums: albums,
                artists: artists,
                fingerprint: fingerprint
            )
        )
        await waitForAllMutations()
        return lastStatus
    }

    func status() -> PlayCountSearchIndexStatus {
        lastStatus
    }

    func purge() async {
        await enqueue(.purge)
    }

    private func waitForAllMutations() async {
        while let tail = mutationTail {
            let observedMutationID = latestMutationID
            await tail.value
            if observedMutationID == latestMutationID { return }
        }
    }

    private func performPurge() async {
        let index = CSSearchableIndex.default()
        lastFingerprint = nil
        do {
            try await index.deleteAppEntities(ofType: SongEntity.self)
            try await index.deleteAppEntities(ofType: AlbumEntity.self)
            try await index.deleteAppEntities(ofType: ArtistEntity.self)
            if #available(iOS 27.0, *) {
                try await index.deleteAppEntities(ofType: SiriAISongEntity.self)
                try await index.deleteAppEntities(ofType: SiriAIAlbumEntity.self)
                try await index.deleteAppEntities(ofType: SiriAIArtistEntity.self)
            }
            lastFingerprint = "purged"
            lastStatus = PlayCountSearchIndexStatus(
                state: .notRun,
                lastUpdated: Date(),
                songCount: 0,
                albumCount: 0,
                artistCount: 0
            )
        } catch {
            lastStatus = PlayCountSearchIndexStatus(
                state: .failed(error.localizedDescription),
                lastUpdated: Date(),
                songCount: 0,
                albumCount: 0,
                artistCount: 0
            )
        }
    }

}

enum PlayCountSearchFingerprint {
    static func make(songs: [TopSong], albums: [TopAlbum], artists: [TopArtist]) -> String {
        func field(_ value: String) -> String { "\(value.utf8.count):\(value)" }

        let songPart = songs.prefix(250).map {
            [String($0.id), $0.title, $0.artist, $0.albumTitle, String($0.playCount), String($0.totalPlayDuration)]
                .map(field)
                .joined(separator: "|")
        }.joined(separator: ",")
        let albumPart = albums.prefix(100).map {
            [String($0.id), $0.title, $0.artist, String($0.playCount), String($0.totalPlayDuration)]
                .map(field)
                .joined(separator: "|")
        }.joined(separator: ",")
        let artistPart = artists.prefix(100).map {
            [String($0.id), $0.name, String($0.playCount), String($0.totalPlayDuration)]
                .map(field)
                .joined(separator: "|")
        }.joined(separator: ",")
        return "\(songPart)#\(albumPart)#\(artistPart)"
    }
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.song)
struct SiriAISongEntity: IndexedEntity {
    static let defaultQuery = SiriAISongEntityQuery()

    let id: String
    var title: String
    var artists: [SiriAIArtistEntity]
    var composers: [SiriAIArtistEntity]
    var composerName: String?
    var album: SiriAIAlbumEntity?
    var albumTitle: String?
    var internationalStandardRecordingCode: String?
    var artistName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(artists.first?.name ?? "Unknown Artist")", image: .init(systemName: "music.note"))
    }

    init(song: TopSong) {
        id = String(song.id)
        artistName = song.artist
        internationalStandardRecordingCode = nil
        albumTitle = song.albumTitle
        album = song.albumPersistentID == 0 ? nil : SiriAIAlbumEntity(song: song)
        composerName = nil
        composers = []
        artists = [SiriAIArtistEntity(song: song)]
        title = song.title
    }
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.artist)
struct SiriAIArtistEntity: IndexedEntity {
    static let defaultQuery = SiriAIArtistEntityQuery()

    let id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: "music.mic"))
    }

    init(song: TopSong) {
        id = Self.identifier(persistentID: song.artistPersistentID, name: song.artist)
        name = song.artist
    }

    init(artist: TopArtist) {
        id = Self.identifier(persistentID: artist.id, name: artist.name)
        name = artist.name
    }

    init(name: String) {
        id = Self.identifier(persistentID: 0, name: name)
        self.name = name
    }

    init(persistentID: UInt64, name: String) {
        id = Self.identifier(persistentID: persistentID, name: name)
        self.name = name
    }

    private static func identifier(persistentID: UInt64, name: String) -> String {
        persistentID == 0 ? "name:\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")))" : String(persistentID)
    }
}

@available(iOS 27.0, *)
@AppEntity(schema: .audio.album)
struct SiriAIAlbumEntity: IndexedEntity {
    static let defaultQuery = SiriAIAlbumEntityQuery()

    let id: String
    var title: String
    var artists: [SiriAIArtistEntity]
    var universalProductCode: String?
    var artistName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: "square.stack"))
    }

    init(song: TopSong) {
        id = String(song.albumPersistentID)
        artistName = song.albumArtist
        universalProductCode = nil
        let albumArtistID = Self.albumArtistPersistentID(song: song)
        artists = song.albumArtist.isEmpty
            ? []
            : [SiriAIArtistEntity(persistentID: albumArtistID, name: song.albumArtist)]
        title = song.albumTitle
    }

    init(album: TopAlbum) {
        id = String(album.id)
        artistName = album.artist
        universalProductCode = nil
        artists = album.artist.isEmpty
            ? []
            : [SiriAIArtistEntity(persistentID: album.artistPersistentID, name: album.artist)]
        title = album.title
    }

    private static func albumArtistPersistentID(song: TopSong) -> UInt64 {
        song.albumArtist.localizedCaseInsensitiveCompare(song.artist) == .orderedSame
            ? song.artistPersistentID
            : 0
    }
}

@available(iOS 27.0, *)
struct SiriAISongEntityQuery: EntityStringQuery {
    func entities(for identifiers: [SiriAISongEntity.ID]) async throws -> [SiriAISongEntity] {
        let requested = Set(identifiers.compactMap(UInt64.init))
        return try PlayCountIntentLibrary().songs().filter { requested.contains($0.id) }.map(SiriAISongEntity.init)
    }

    func entities(matching string: String) async throws -> [SiriAISongEntity] {
        try PlayCountIntentLibrary().songs()
            .filter { $0.title.localizedStandardContains(string) || $0.artist.localizedStandardContains(string) }
            .sorted { $0.playCount > $1.playCount }
            .prefix(25)
            .map(SiriAISongEntity.init)
    }

    func suggestedEntities() async throws -> [SiriAISongEntity] {
        try PlayCountIntentLibrary().songs().sorted { $0.playCount > $1.playCount }.prefix(20).map(SiriAISongEntity.init)
    }
}

@available(iOS 27.0, *)
struct SiriAIArtistEntityQuery: EntityQuery {
    func entities(for identifiers: [SiriAIArtistEntity.ID]) async throws -> [SiriAIArtistEntity] {
        let requested = Set(identifiers)
        let library = PlayCountIntentLibrary()
        let songArtists = try library.songs().flatMap { song in
            let albumArtistID = song.albumArtist.localizedCaseInsensitiveCompare(song.artist) == .orderedSame
                ? song.artistPersistentID
                : 0
            return [
                SiriAIArtistEntity(song: song),
                SiriAIArtistEntity(persistentID: albumArtistID, name: song.albumArtist)
            ]
        }
        let groupedArtists = try library.artists().map(SiriAIArtistEntity.init)
        return (songArtists + groupedArtists)
            .reduce(into: [String: SiriAIArtistEntity]()) { $0[$1.id] = $1 }
            .values
            .filter { requested.contains($0.id) }
    }
}

@available(iOS 27.0, *)
struct SiriAIAlbumEntityQuery: EntityQuery {
    func entities(for identifiers: [SiriAIAlbumEntity.ID]) async throws -> [SiriAIAlbumEntity] {
        let requested = Set(identifiers.compactMap(UInt64.init))
        return try PlayCountIntentLibrary().songs()
            .filter { requested.contains($0.albumPersistentID) }
            .reduce(into: [UInt64: TopSong]()) { $0[$1.albumPersistentID] = $1 }
            .values.map(SiriAIAlbumEntity.init)
    }
}
