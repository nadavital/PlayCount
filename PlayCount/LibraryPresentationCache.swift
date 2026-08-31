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
        let discNumber: Int?
        let trackNumber: Int
        let playbackStoreID: String?

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
            discNumber = song.discNumber
            trackNumber = song.trackNumber
            playbackStoreID = song.playbackStoreID
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
                discNumber: discNumber ?? 0,
                trackNumber: trackNumber,
                playbackStoreID: playbackStoreID ?? ""
            )
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let maximumCacheBytes: Int
    private let lock = NSLock()

    init(fileManager: FileManager = .default, directoryURL: URL? = nil, maximumCacheBytes: Int = 32 * 1_024 * 1_024) {
        self.fileManager = fileManager
        self.maximumCacheBytes = max(1, min(maximumCacheBytes, Int.max - 1))
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
        // This is disposable presentation data, never recap history. A corrupt
        // or unusually large cache must fall back to Music, not exhaust memory.
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maximumCacheBytes + 1),
              data.count <= maximumCacheBytes,
              let stored = try? decoder.decode(StoredSnapshot.self, from: data),
              stored.schemaVersion == 1,
              !stored.songs.isEmpty,
              stored.songs.allSatisfy({
                  $0.playCount >= 0 && $0.skipCount >= 0 &&
                  $0.playbackDuration.isFinite && $0.playbackDuration >= 0 &&
                  $0.totalPlayDuration.isFinite && $0.totalPlayDuration >= 0
              }) else {
            return nil
        }
        var totalPlays = 0
        var totalDuration: TimeInterval = 0
        for song in stored.songs {
            let sum = totalPlays.addingReportingOverflow(song.playCount)
            totalDuration += song.totalPlayDuration
            guard !sum.overflow, totalDuration.isFinite else { return nil }
            totalPlays = sum.partialValue
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
        guard let data = try? encoder.encode(stored), data.count <= maximumCacheBytes else { return }
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
