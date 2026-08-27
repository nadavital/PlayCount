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
}

extension View {
    func playCountSongEntityIdentifier(_: TopSong) -> some View {
        self
    }

    func playCountAlbumEntityIdentifier(_: TopAlbum) -> some View {
        self
    }

    func playCountArtistEntityIdentifier(_: TopArtist) -> some View {
        self
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

            try await index.indexAppEntities(Array(songs.prefix(maximumIndexedSongs)).map(SongEntity.init), priority: 1)
            try await index.indexAppEntities(Array(albums.prefix(maximumIndexedAlbums)).map(AlbumEntity.init))
            try await index.indexAppEntities(Array(artists.prefix(maximumIndexedArtists)).map(ArtistEntity.init))
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
