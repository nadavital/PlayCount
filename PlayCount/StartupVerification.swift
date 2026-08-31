#if DEBUG
import Foundation
import MediaPlayer

/// An opt-in UI-test source that still exercises the production startup pipeline.
/// Every launch owns disposable storage and never reads Music or syncs CloudKit.
enum StartupVerification {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-PlayCountStartupVerification")
    }

    @MainActor
    static func makeManager() -> MediaLibraryManager {
        let arguments = ProcessInfo.processInfo.arguments
        let hasCache = arguments.contains("-PlayCountStartupCached")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountStartupUI-\(UUID())", isDirectory: true)
        let cache = LibraryPresentationCache(directoryURL: directory)
        if hasCache {
            cache.save(songs: songs(live: false))
        }

        return MediaLibraryManager(
            snapshotStore: MonthlyRecapSnapshotStore(directoryURL: directory),
            weeklyInsightStore: WeeklyRecapInsightStore(directoryURL: directory),
            milestoneLedger: MediaMilestoneLedger(fileURL: directory.appendingPathComponent("medals.sqlite")),
            presentationCache: cache,
            recapCloudSyncService: nil,
            startsAutomatically: false,
            libraryAccess: .init(
                authorizationStatus: { .authorized },
                readSongs: {
                    // Deliberately block the injected worker, not the main actor.
                    NSLog("StartupVerification: worker read began")
                    // Leave room for XCTest launch/idle/screenshot overhead so
                    // interactions can be asserted before this read completes.
                    Thread.sleep(forTimeInterval: 12)
                    NSLog("StartupVerification: worker read finished")
                    return songs(live: true)
                }
            )
        )
    }

    private static func songs(live: Bool) -> [TopSong] {
        (1...30).map { index in
            let plays = 100 - index + (live ? 1 : 0)
            return TopSong(
                id: UInt64(index),
                title: index == 1 ? "First Light" : "Track \(index)",
                artist: "Startup Ensemble",
                albumTitle: "Morning Signals",
                albumArtist: "Startup Ensemble",
                playCount: plays,
                skipCount: 0,
                totalPlayDuration: Double(plays) * 180,
                playbackDuration: 180,
                lastPlayedDate: nil,
                dateAdded: nil,
                artwork: nil,
                albumPersistentID: 1,
                artistPersistentID: 1,
                trackNumber: index
            )
        }
    }
}
#endif
