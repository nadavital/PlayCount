import Foundation

struct LibraryPresentationSnapshot {
    let capturedAt: Date
    let songs: [TopSong]
}

final class LibraryPresentationCache: @unchecked Sendable {
    static let shared = LibraryPresentationCache()

    private struct StoredSnapshot: Codable {
        let schemaVersion: Int
        let capturedAt: Date
        let songs: [StoredSong]
    }

    private struct StoredSong: Codable {
        let id: UInt64
        let title: String
        let artist: String
        let albumTitle: String
        let albumArtist: String
        let playCount: Int
        let skipCount: Int
        let totalPlayDuration: TimeInterval
        let playbackDuration: TimeInterval
        let lastPlayedDate: Date?
        let dateAdded: Date?
        let albumPersistentID: UInt64
        let artistPersistentID: UInt64
        let trackNumber: Int

        init(song: TopSong) {
            id = song.id
            title = song.title
            artist = song.artist
            albumTitle = song.albumTitle
            albumArtist = song.albumArtist
            playCount = song.playCount
            skipCount = song.skipCount
            totalPlayDuration = song.totalPlayDuration
            playbackDuration = song.playbackDuration
            lastPlayedDate = song.lastPlayedDate
            dateAdded = song.dateAdded
            albumPersistentID = song.albumPersistentID
            artistPersistentID = song.artistPersistentID
            trackNumber = song.trackNumber
        }

        var topSong: TopSong {
            TopSong(
                id: id,
                title: title,
                artist: artist,
                albumTitle: albumTitle,
                albumArtist: albumArtist,
                playCount: playCount,
                skipCount: skipCount,
                totalPlayDuration: totalPlayDuration,
                playbackDuration: playbackDuration,
                lastPlayedDate: lastPlayedDate,
                dateAdded: dateAdded,
                artwork: nil,
                albumPersistentID: albumPersistentID,
                artistPersistentID: artistPersistentID,
                trackNumber: trackNumber
            )
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        let directory = directoryURL
            ?? (fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory)
                .appendingPathComponent("PlayCount", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library-presentation.json")
    }

    func load() -> LibraryPresentationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    private func loadLocked() -> LibraryPresentationSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? decoder.decode(StoredSnapshot.self, from: data),
              stored.schemaVersion == 1,
              !stored.songs.isEmpty else {
            return nil
        }
        return LibraryPresentationSnapshot(
            capturedAt: stored.capturedAt,
            songs: stored.songs.map { $0.topSong }
        )
    }

    func load(maximumAge: TimeInterval, now: Date = Date()) -> LibraryPresentationSnapshot? {
        guard let snapshot = load(),
              now.timeIntervalSince(snapshot.capturedAt) <= maximumAge else {
            return nil
        }
        return snapshot
    }

    func save(
        songs: [TopSong],
        capturedAt: Date = Date(),
        shouldCommit: @Sendable () -> Bool = { true }
    ) {
        guard !songs.isEmpty else {
            lock.lock()
            defer { lock.unlock() }
            guard shouldCommit() else { return }
            try? fileManager.removeItem(at: fileURL)
            return
        }
        let stored = StoredSnapshot(
            schemaVersion: 1,
            capturedAt: capturedAt,
            songs: songs.map(StoredSong.init(song:))
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stored) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard shouldCommit() else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    func remove() {
        lock.lock()
        defer { lock.unlock() }
        try? fileManager.removeItem(at: fileURL)
    }
}
