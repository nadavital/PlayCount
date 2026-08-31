import XCTest
import UIKit
import MediaPlayer
@testable import PlayCount

final class MediaLibraryManagerIndexTests: XCTestCase {
    @MainActor
    func testDetailUpdatesPublishForImmediateLibraryAndMetricChanges() {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let initialRevision = manager.detailPresentationUpdates.revision

        manager.debugLoadLibraryFixture(
            songs: [song(id: 1, title: "Song", artist: "Artist", playCount: 1)],
            albums: [],
            artists: []
        )
        XCTAssertEqual(manager.detailPresentationUpdates.revision, initialRevision + 1)

        manager.sortMetric = .listenTime
        XCTAssertEqual(manager.detailPresentationUpdates.revision, initialRevision + 2)
    }

    @MainActor
    func testDetailUpdatesPublishForRecapChanges() {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let initialRevision = manager.detailPresentationUpdates.revision

        manager.debugPublishRecapFixture(.empty(for: Date(timeIntervalSince1970: 1_896_134_400)))

        XCTAssertEqual(manager.detailPresentationUpdates.revision, initialRevision + 1)
    }

    @MainActor
    func testMetricChangeResortsDeferredDetailIndexes() {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let owner = UUID()
        let album = album(
            id: 100,
            title: "Album",
            artist: "Artist",
            playCount: 15,
            artistPersistentID: 10
        )
        let playLeader = song(
            id: 1,
            title: "Play Leader",
            artist: "Artist",
            playCount: 10,
            totalPlayDuration: 600,
            albumPersistentID: album.id,
            artistPersistentID: 10
        )
        let timeLeader = song(
            id: 2,
            title: "Time Leader",
            artist: "Artist",
            playCount: 5,
            totalPlayDuration: 1_800,
            albumPersistentID: album.id,
            artistPersistentID: 10
        )

        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(
            songs: [playLeader, timeLeader],
            albums: [album],
            artists: [artist(id: 10, name: "Artist")]
        )

        XCTAssertEqual(manager.songs(for: album).map(\.id), [playLeader.id, timeLeader.id])

        manager.sortMetric = .listenTime

        XCTAssertEqual(manager.songs(for: album).map(\.id), [timeLeader.id, playLeader.id])
    }

    func testZeroPersistentIDsUseMetadataFallbackInsteadOfColliding() {
        let firstSong = song(id: 0, title: "First Song", artist: "First Artist", playCount: 2)
        let secondSong = song(id: 0, title: "Second Song", artist: "Second Artist", playCount: 3)
        let firstAlbum = album(id: 0, title: "First Album", artist: "First Artist", playCount: 2, artistPersistentID: 0)
        let secondAlbum = album(id: 0, title: "Second Album", artist: "Second Artist", playCount: 3, artistPersistentID: 0)
        let firstArtist = artist(id: 0, name: "First Artist")
        let secondArtist = artist(id: 0, name: "Second Artist")
        let manager = manager(
            songs: [firstSong, secondSong],
            albums: [firstAlbum, secondAlbum],
            artists: [firstArtist, secondArtist]
        )

        XCTAssertNil(manager.song(withPersistentID: 0))
        XCTAssertEqual(manager.song(matchingTitle: secondSong.title, artist: secondSong.artist)?.title, secondSong.title)
        XCTAssertNil(manager.album(withPersistentID: 0))
        XCTAssertEqual(manager.album(matchingTitle: secondAlbum.title, artist: secondAlbum.artist)?.title, secondAlbum.title)
        XCTAssertNil(manager.artist(withPersistentID: 0))
        XCTAssertEqual(manager.artist(matchingName: secondArtist.name)?.name, secondArtist.name)
    }

    @MainActor
    func testDetailPresentationDefersBulkLibraryPublicationUntilDismissal() async {
        let manager = MediaLibraryManager(
            recapCloudSyncService: nil,
            startsAutomatically: false
        )
        let cachedSong = song(id: 1, title: "Cached", artist: "Artist", playCount: 1)
        let refreshedSong = song(id: 2, title: "Refreshed", artist: "Artist", playCount: 2)
        manager.debugLoadLibraryFixture(songs: [cachedSong], albums: [], artists: [])

        let owner = UUID()
        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(songs: [refreshedSong], albums: [], artists: [])

        XCTAssertEqual(manager.topSongs.map(\.id), [cachedSong.id])

        manager.setDetailPresentationActive(false, owner: owner)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(manager.topSongs.map(\.id), [refreshedSong.id])
    }

    @MainActor
    func testDeferredLibraryPublicationKeepsItsMatchingRecap() async {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let owner = UUID()
        let refreshedSong = song(id: 2, title: "Refreshed", artist: "Artist", playCount: 2)
        let refreshedRecap = MonthlyRecap.empty(
            for: Date(timeIntervalSince1970: 1_893_456_000)
        )

        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(
            songs: [refreshedSong],
            albums: [],
            artists: [],
            recap: refreshedRecap
        )
        manager.setDetailPresentationActive(false, owner: owner)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(manager.monthlyRecap.monthStart, refreshedRecap.monthStart)
    }

    @MainActor
    func testLaterRecapPreparationUpdatesDeferredLibraryPayload() async {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let owner = UUID()
        let refreshedSong = song(id: 2, title: "Refreshed", artist: "Artist", playCount: 2)
        let preparedRecap = MonthlyRecap.empty(
            for: Date(timeIntervalSince1970: 1_896_134_400)
        )

        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(songs: [refreshedSong], albums: [], artists: [])
        manager.debugPublishRecapFixture(preparedRecap)

        XCTAssertEqual(manager.detailMonthlyRecap.monthStart, preparedRecap.monthStart)

        manager.setDetailPresentationActive(false, owner: owner)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(manager.monthlyRecap.monthStart, preparedRecap.monthStart)
    }

    @MainActor
    func testNewerImmediateLibraryPublicationCancelsOlderDismissalFlush() async {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let owner = UUID()
        let deferredSong = song(id: 2, title: "Deferred", artist: "Artist", playCount: 2)
        let newestSong = song(id: 3, title: "Newest", artist: "Artist", playCount: 3)

        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(songs: [deferredSong], albums: [], artists: [])
        manager.setDetailPresentationActive(false, owner: owner)
        manager.debugLoadLibraryFixture(songs: [newestSong], albums: [], artists: [])
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(manager.topSongs.map(\.id), [newestSong.id])
    }

    @MainActor
    func testOverlappingDetailPresentationsWaitForEveryOwnerToDismiss() async {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let firstOwner = UUID()
        let secondOwner = UUID()
        let cachedSong = song(id: 1, title: "Cached", artist: "Artist", playCount: 1)
        let refreshedSong = song(id: 2, title: "Refreshed", artist: "Artist", playCount: 2)
        manager.debugLoadLibraryFixture(songs: [cachedSong], albums: [], artists: [])

        manager.setDetailPresentationActive(true, owner: firstOwner)
        manager.setDetailPresentationActive(true, owner: secondOwner)
        manager.debugLoadLibraryFixture(songs: [refreshedSong], albums: [], artists: [])
        manager.setDetailPresentationActive(false, owner: firstOwner)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(manager.topSongs.map(\.id), [cachedSong.id])

        manager.setDetailPresentationActive(false, owner: secondOwner)
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(manager.topSongs.map(\.id), [refreshedSong.id])
    }

    @MainActor
    func testColdLaunchDetailReadsDeferredIndexesWithoutBulkPublication() {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let owner = UUID()
        let deferredArtist = artist(id: 30, name: "Artist", playCount: 4)
        let deferredAlbum = album(
            id: 20,
            title: "Album",
            artist: deferredArtist.name,
            playCount: 4,
            artistPersistentID: deferredArtist.id
        )
        let deferredSong = song(
            id: 10,
            title: "Song",
            artist: deferredArtist.name,
            playCount: 4,
            albumPersistentID: deferredAlbum.id,
            artistPersistentID: deferredArtist.id
        )

        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(
            songs: [deferredSong],
            albums: [deferredAlbum],
            artists: [deferredArtist]
        )

        XCTAssertTrue(manager.topSongs.isEmpty)
        XCTAssertEqual(manager.album(withPersistentID: deferredAlbum.id)?.id, deferredAlbum.id)
        XCTAssertEqual(manager.artist(withPersistentID: deferredArtist.id)?.id, deferredArtist.id)
        XCTAssertEqual(manager.songs(for: deferredAlbum).map(\.id), [deferredSong.id])
        XCTAssertEqual(manager.songs(for: deferredArtist).map(\.id), [deferredSong.id])
        XCTAssertEqual(manager.playCountRank(of: deferredSong), 1)
        XCTAssertEqual(manager.detailPresentationUpdates.revision, 1)
    }

    @MainActor
    func testCloudRecapHydrationPrefersDeferredFreshLibrary() {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let owner = UUID()
        let publishedSong = song(id: 1, title: "Published", artist: "Artist", playCount: 1)
        let deferredSong = song(id: 2, title: "Deferred", artist: "Artist", playCount: 2)
        manager.debugLoadLibraryFixture(songs: [publishedSong], albums: [], artists: [])

        manager.setDetailPresentationActive(true, owner: owner)
        manager.debugLoadLibraryFixture(songs: [deferredSong], albums: [], artists: [])

        XCTAssertEqual(manager.topSongs.map(\.id), [publishedSong.id])
        XCTAssertEqual(manager.debugRecapHydrationSongIDs, [deferredSong.id])
    }

    func testNowPlayingDisplayEquivalenceDoesNotDependOnArtworkObjectIdentity() {
        let firstArtwork = MPMediaItemArtwork(boundsSize: CGSize(width: 100, height: 100)) { _ in UIImage() }
        let secondArtwork = MPMediaItemArtwork(boundsSize: CGSize(width: 100, height: 100)) { _ in UIImage() }
        let first = MediaLibraryManager.NowPlayingState(
            title: "Current Song",
            subtitle: "Artist — Album",
            artwork: firstArtwork,
            duration: 180,
            isPlaying: true,
            playCount: 12,
            song: nil
        )
        let second = MediaLibraryManager.NowPlayingState(
            title: "Current Song",
            subtitle: "Artist — Album",
            artwork: secondArtwork,
            duration: 180,
            isPlaying: true,
            playCount: 12,
            song: nil
        )
        let missingArtwork = MediaLibraryManager.NowPlayingState(
            title: "Current Song",
            subtitle: "Artist — Album",
            artwork: nil,
            duration: 180,
            isPlaying: true,
            playCount: 12,
            song: nil
        )

        XCTAssertTrue(first.isDisplayEquivalent(to: second))
        XCTAssertFalse(first.isDisplayEquivalent(to: missingArtwork))
    }

    @MainActor
    func testEveryRecapShareTemplateRendersCompleteStoryCanvas() throws {
        let songs = (1...10).map { index in
            MonthlyRecap.RankedSong(
                id: UInt64(index),
                title: "A Long Song Title \(index)",
                artist: "Artist \(index)",
                albumTitle: "Album \(index)",
                playDelta: 50 - index,
                skipDelta: 0,
                listeningDuration: TimeInterval(7_560 - index * 60),
                artwork: nil
            )
        }
        let groups = (1...10).map { index in
            MonthlyRecap.RankedGroup(
                id: "group-\(index)",
                title: "A Long Album or Artist Name \(index)",
                subtitle: "Subtitle \(index)",
                playDelta: 50 - index,
                listeningDuration: TimeInterval(7_560 - index * 60),
                artwork: nil
            )
        }
        let songGainers = songs.map { song in
            MonthlyRecap.MovementSong(
                id: song.id,
                title: song.title,
                artist: song.artist,
                playDelta: song.playDelta,
                rankChange: 20,
                currentRank: 4,
                previousRank: 24,
                artwork: nil
            )
        }
        let groupGainers = groups.map { group in
            MonthlyRecap.MovementGroup(
                id: group.id,
                title: group.title,
                subtitle: group.subtitle,
                playDelta: group.playDelta,
                rankChange: 20,
                currentRank: 4,
                previousRank: 24,
                artwork: nil
            )
        }
        let recap = MonthlyRecap(
            monthStart: Date(),
            generatedAt: Date(),
            lastCaptureReason: .foreground,
            trackingStart: Date(),
            snapshotCount: 2,
            totalPlayDelta: 218,
            totalSkipDelta: 3,
            totalListeningDuration: 45_660,
            playedSongCount: 12,
            newSongCount: 1,
            topSongs: songs,
            topArtists: groups,
            topAlbums: groups,
            biggestGainers: songGainers,
            biggestAlbumGainers: groupGainers,
            biggestArtistGainers: groupGainers,
            topNewSongs: []
        )
        let palette = RecapSharePalette(artworks: [], fallbackSeed: 42)
        let calendar = Calendar(identifier: .gregorian)
        let yearStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let trendPoints = (0..<12).compactMap { offset -> RecapShareTrendPoint? in
            guard let month = calendar.date(byAdding: .month, value: offset, to: yearStart) else { return nil }
            return RecapShareTrendPoint(
                month: month,
                plays: 120 + offset * 18,
                listeningMinutes: Double(410 + offset * 56)
            )
        }

        for template in RecapShareTemplate.allCases {
            let image = try XCTUnwrap(
                RecapShareRenderer.image(
                    recap: recap,
                    periodTitle: "July 2026",
                    palette: palette,
                    template: template,
                    trendPoints: trendPoints
                )
            )
            XCTAssertEqual(image.size.width, 360, accuracy: 0.5, "\(template)")
            XCTAssertEqual(image.size.height, 640, accuracy: 0.5, "\(template)")
            XCTAssertEqual(image.cgImage?.width, 1_080, "\(template)")
            XCTAssertEqual(image.cgImage?.height, 1_920, "\(template)")
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 10_000, "\(template)")
        }

        for category in RecapShareGainerCategory.allCases {
            let image = try XCTUnwrap(
                RecapShareRenderer.image(
                    recap: recap,
                    periodTitle: "July 2026",
                    palette: palette,
                    template: .biggestGainers,
                    gainerCategory: category
                )
            )
            XCTAssertEqual(image.cgImage?.width, 1_080, "\(category)")
            XCTAssertEqual(image.cgImage?.height, 1_920, "\(category)")
        }
    }

    @MainActor
    func testRecapOverviewExportResolvesArtworkBeforeRendering() throws {
        var artworkRequestCount = 0
        let sourceImage = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400)).image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        let artwork = MPMediaItemArtwork(boundsSize: sourceImage.size) { _ in
            artworkRequestCount += 1
            return sourceImage
        }
        let song = MonthlyRecap.RankedSong(
            id: 1,
            title: "Green Light",
            artist: "Artist",
            albumTitle: "Album",
            playDelta: 42,
            skipDelta: 0,
            listeningDuration: 9_000,
            artwork: artwork
        )
        let recap = MonthlyRecap(
            monthStart: Date(),
            generatedAt: Date(),
            lastCaptureReason: .foreground,
            trackingStart: Date(),
            snapshotCount: 2,
            totalPlayDelta: 42,
            totalSkipDelta: 0,
            totalListeningDuration: 9_000,
            playedSongCount: 1,
            newSongCount: 0,
            topSongs: [song],
            topArtists: [],
            topAlbums: [],
            biggestGainers: [],
            topNewSongs: []
        )

        let image = RecapShareRenderer.image(
            recap: recap,
            periodTitle: "July 2026",
            palette: RecapSharePalette(artworks: [], fallbackSeed: 7),
            template: .overview
        )

        XCTAssertNotNil(image)
        XCTAssertGreaterThan(artworkRequestCount, 0, "Export must resolve cover art synchronously before ImageRenderer snapshots the card")
    }

    func testInitializationDefersStoredRecapLoading() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountLaunch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MonthlyRecapSnapshotStore(directoryURL: directory, deviceIdentifier: "launch-test")
        let now = Date()
        _ = store.record(
            songs: [song(id: 1, title: "Stored Song", artist: "Nova Lane", playCount: 10)],
            at: now.addingTimeInterval(-3_600),
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Stored Song", artist: "Nova Lane", playCount: 14)],
            at: now,
            reason: .foreground
        )
        XCTAssertTrue(store.currentMonthRecap(at: now).hasActivity)

        let manager = MediaLibraryManager(
            snapshotStore: store,
            recapCloudSyncService: nil,
            startsAutomatically: false
        )

        XCTAssertFalse(manager.monthlyRecap.hasActivity)
        XCTAssertEqual(manager.availableRecapMonths.count, 1)
        XCTAssertFalse(manager.hasLoadedInitialSnapshot)
        XCTAssertEqual(manager.loadingStage, .idle)
    }

    func testIntentSnapshotLoadsPriorMonthWithoutStartingLibraryRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountIntentHydration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.dateInterval(of: .month, for: now)!.start
        let priorMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!
        let baseline = calendar.date(byAdding: .hour, value: 1, to: priorMonth)!
        let latest = calendar.date(byAdding: .hour, value: 2, to: priorMonth)!
        let store = MonthlyRecapSnapshotStore(directoryURL: directory, deviceIdentifier: "intent-test")
        _ = store.record(
            songs: [song(id: 1, title: "Prior Song", artist: "Nova Lane", playCount: 10)],
            at: baseline,
            reason: .appLaunch
        )
        _ = store.record(
            songs: [song(id: 1, title: "Prior Song", artist: "Nova Lane", playCount: 15)],
            at: latest,
            reason: .foreground
        )

        let manager = MediaLibraryManager(
            snapshotStore: store,
            recapCloudSyncService: nil,
            startsAutomatically: false
        )
        let recaps = await manager.storedRecapsForIntents()
        let latestUsable = PlayCountIntentRecaps.latestUsable(from: recaps)
        XCTAssertEqual(latestUsable?.monthStart, calendar.startOfMonth(containing: priorMonth))
        XCTAssertEqual(latestUsable?.topSongs.first?.playDelta, 5)
        XCTAssertFalse(manager.hasLoadedInitialSnapshot)
    }

    func testRecapPageSwitchUsesCompactMemoryCacheWithoutLoadingFullSnapshotStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountRecapSwitch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let calendar = Calendar.current
        let writer = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "recap-switch-writer"
        )
        let mayStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12)))
        let mayEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 12)))
        let julyStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12)))
        let julyEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 12)))
        _ = writer.record(songs: [song(id: 1, title: "May Song", artist: "Artist", playCount: 10)], at: mayStart, reason: .appLaunch)
        _ = writer.record(songs: [song(id: 1, title: "May Song", artist: "Artist", playCount: 16)], at: mayEnd, reason: .foreground)
        _ = writer.record(songs: [song(id: 2, title: "July Song", artist: "Artist", playCount: 4)], at: julyStart, reason: .appLaunch)
        _ = writer.record(songs: [song(id: 2, title: "July Song", artist: "Artist", playCount: 11)], at: julyEnd, reason: .foreground)

        let coldStore = MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: calendar,
            deviceIdentifier: "recap-switch-reader"
        )
        let presentation = coldStore.cachedRecapPresentation(through: julyEnd)
        let manager = MediaLibraryManager(
            snapshotStore: coldStore,
            recapCloudSyncService: nil,
            startsAutomatically: false
        )

        XCTAssertFalse(coldStore.debugHasLoadedFullSnapshotStore)
        XCTAssertEqual(presentation.monthlyRecaps.count, 2)
        XCTAssertEqual(presentation.availableMonthStarts.count, 2)
        XCTAssertEqual(calendar.component(.month, from: presentation.availableMonthStarts[1]), 7)
        manager.seedRecapCaches(from: presentation)

        let cachedMay = try XCTUnwrap(presentation.monthlyRecaps.first {
            calendar.isDate($0.monthStart, equalTo: mayEnd, toGranularity: .month)
        })
        let cachedJuly = try XCTUnwrap(presentation.monthlyRecaps.first {
            calendar.isDate($0.monthStart, equalTo: julyEnd, toGranularity: .month)
        })
        let cachedYear = try XCTUnwrap(presentation.yearlyRecaps[2026])
        XCTAssertEqual(manager.recap(forMonthContaining: mayEnd), cachedMay)
        XCTAssertEqual(manager.recap(forMonthContaining: julyEnd), cachedJuly)
        XCTAssertEqual(manager.yearlyRecap(for: 2026), cachedYear)
        XCTAssertEqual(manager.yearToDateRecap(through: mayEnd).totalPlayDelta, 6)
        XCTAssertEqual(manager.yearToDateRecap(through: julyEnd).totalPlayDelta, 13)
        XCTAssertEqual(
            manager.yearToDateRecap(through: julyEnd).topSongs.map(\.title),
            ["July Song", "May Song"]
        )
        XCTAssertFalse(coldStore.debugHasLoadedFullSnapshotStore)
    }

    func testAlbumsForArtistMergesIDAndNameMatches() {
        let artist = artist(id: 10, name: "Nova Lane")
        let manager = manager(
            songs: [],
            albums: [
                album(id: 1, title: "ID Match", artist: "Nova Lane", playCount: 40, artistPersistentID: 10),
                album(id: 2, title: "Name Match", artist: "Nova Lane", playCount: 90, artistPersistentID: 999),
                album(id: 3, title: "Other Artist", artist: "Mira Vale", playCount: 120, artistPersistentID: 20)
            ],
            artists: [artist]
        )

        XCTAssertEqual(manager.albums(for: artist).map(\.title), ["Name Match", "ID Match"])
    }

    func testSongsForArtistPreservesZeroIDNameFallbackWhenIDMatchesExist() {
        let artist = artist(id: 10, name: "Nova Lane")
        let manager = manager(
            songs: [
                song(id: 1, title: "ID Song", artist: "Nova Lane", playCount: 40, artistPersistentID: 10),
                song(id: 2, title: "Fallback Song", artist: "Nova Lane", playCount: 90, artistPersistentID: 0),
                song(id: 3, title: "Different ID Song", artist: "Nova Lane", playCount: 120, artistPersistentID: 999)
            ],
            albums: [],
            artists: [artist]
        )

        XCTAssertEqual(manager.songs(for: artist).map(\.title), ["Fallback Song", "ID Song"])
    }

    func testSongsForAlbumMergesIDAndLegacyZeroIDFallbackMatches() {
        let album = album(id: 100, title: "Glass Coast", artist: "Nova Lane", playCount: 40, artistPersistentID: 10)
        let manager = manager(
            songs: [
                song(id: 1, title: "ID Track", artist: "Nova Lane", albumTitle: "Glass Coast", playCount: 40, albumPersistentID: 100, artistPersistentID: 10),
                song(id: 2, title: "Fallback Track", artist: "Nova Lane", albumTitle: "Glass Coast", playCount: 90, albumPersistentID: 0, artistPersistentID: 10),
                song(id: 3, title: "Other Track", artist: "Mira Vale", albumTitle: "Glass Coast", playCount: 120, albumPersistentID: 0, artistPersistentID: 20)
            ],
            albums: [album],
            artists: [artist(id: 10, name: "Nova Lane")]
        )

        XCTAssertEqual(manager.songs(for: album).map(\.title), ["Fallback Track", "ID Track"])
    }

    func testSongsForAlbumUsesAlbumArtistForIDLessCompilationFallbacks() {
        let album = album(id: 0, title: "Compilation", artist: "Various Artists", playCount: 12, artistPersistentID: 0)
        let manager = manager(
            songs: [
                song(
                    id: 1,
                    title: "Track A",
                    artist: "Track Artist A",
                    albumArtist: "Various Artists",
                    albumTitle: "Compilation",
                    playCount: 5,
                    albumPersistentID: 0,
                    artistPersistentID: 100
                ),
                song(
                    id: 2,
                    title: "Track B",
                    artist: "Track Artist B",
                    albumArtist: "Various Artists",
                    albumTitle: "Compilation",
                    playCount: 7,
                    albumPersistentID: 0,
                    artistPersistentID: 200
                )
            ],
            albums: [album],
            artists: []
        )

        XCTAssertEqual(manager.songs(for: album).map(\.title), ["Track B", "Track A"])
    }

    func testRankMapsUseSameTieBreakersAsVisibleSongOrder() {
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let shorterRecentSong = song(
            id: 1,
            title: "Shorter Recent Song",
            artist: "Nova Lane",
            playCount: 10,
            totalPlayDuration: 100,
            lastPlayedDate: newerDate,
            artistPersistentID: 10
        )
        let longerOlderSong = song(
            id: 2,
            title: "Longer Older Song",
            artist: "Nova Lane",
            playCount: 10,
            totalPlayDuration: 200,
            lastPlayedDate: olderDate,
            artistPersistentID: 10
        )
        let manager = manager(
            songs: [shorterRecentSong, longerOlderSong],
            albums: [],
            artists: [artist(id: 10, name: "Nova Lane")]
        )

        XCTAssertEqual(manager.topSongs.map(\.title), ["Longer Older Song", "Shorter Recent Song"])
        XCTAssertEqual(manager.playCountRank(of: longerOlderSong), 1)
        XCTAssertEqual(manager.playCountRank(of: shorterRecentSong), 2)

        manager.sortMetric = .listenTime

        XCTAssertEqual(manager.topSongs.map(\.title), ["Longer Older Song", "Shorter Recent Song"])
        XCTAssertEqual(manager.listenTimeRank(of: longerOlderSong), 1)
        XCTAssertEqual(manager.listenTimeRank(of: shorterRecentSong), 2)
    }

    @MainActor
    func testRecentlyPlayedSongsArePreparedByRecencyAndExcludeUnknownDates() {
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let manager = manager(
            songs: [
                song(id: 1, title: "Older", artist: "Nova Lane", playCount: 30, lastPlayedDate: olderDate),
                song(id: 2, title: "Unknown", artist: "Nova Lane", playCount: 100, lastPlayedDate: nil),
                song(id: 3, title: "Newer", artist: "Nova Lane", playCount: 1, lastPlayedDate: newerDate)
            ],
            albums: [],
            artists: []
        )

        XCTAssertEqual(manager.recentlyPlayedSongs.map(\.title), ["Newer", "Older"])
    }

    func testRankMapsUseSameTieBreakersAsVisibleAlbumAndArtistOrder() {
        let zAlbum = album(id: 1, title: "Z Album", artist: "Nova Lane", playCount: 10, totalPlayDuration: 100, artistPersistentID: 10)
        let aAlbum = album(id: 2, title: "A Album", artist: "Nova Lane", playCount: 10, totalPlayDuration: 100, artistPersistentID: 10)
        let zArtist = artist(id: 10, name: "Z Artist", playCount: 10, totalPlayDuration: 100)
        let aArtist = artist(id: 11, name: "A Artist", playCount: 10, totalPlayDuration: 100)
        let manager = manager(
            songs: [],
            albums: [zAlbum, aAlbum],
            artists: [zArtist, aArtist]
        )

        XCTAssertEqual(manager.topAlbums.map(\.title), ["A Album", "Z Album"])
        XCTAssertEqual(manager.playCountRank(of: aAlbum), 1)
        XCTAssertEqual(manager.playCountRank(of: zAlbum), 2)
        XCTAssertEqual(manager.topArtists.map(\.name), ["A Artist", "Z Artist"])
        XCTAssertEqual(manager.playCountRank(of: aArtist), 1)
        XCTAssertEqual(manager.playCountRank(of: zArtist), 2)
    }

    func testDerivedAlbumsPreserveAlbumArtistForCompilationAlbums() {
        let firstTrack = song(
            id: 1,
            title: "Track A",
            artist: "Track Artist A",
            albumArtist: "Various Artists",
            albumTitle: "Compilation",
            playCount: 5,
            albumPersistentID: 42,
            artistPersistentID: 100
        )
        let secondTrack = song(
            id: 2,
            title: "Track B",
            artist: "Track Artist B",
            albumArtist: "Various Artists",
            albumTitle: "Compilation",
            playCount: 7,
            albumPersistentID: 42,
            artistPersistentID: 200
        )

        let albums = MediaLibraryManager.debugAlbumsDerivedFromSongs([firstTrack, secondTrack])

        XCTAssertEqual(albums.count, 1)
        XCTAssertEqual(albums.first?.title, "Compilation")
        XCTAssertEqual(albums.first?.artist, "Various Artists")
        XCTAssertEqual(albums.first?.artistPersistentID, 0)
        XCTAssertEqual(albums.first?.playCount, 12)
    }

    func testDerivedAlbumsPreserveArtistIDForSingleArtistAlbums() {
        let firstTrack = song(
            id: 1,
            title: "Track A",
            artist: "Nova Lane",
            albumArtist: "Nova Lane",
            albumTitle: "Glass Coast",
            playCount: 5,
            albumPersistentID: 42,
            artistPersistentID: 100
        )
        let secondTrack = song(
            id: 2,
            title: "Track B",
            artist: "Nova Lane",
            albumArtist: "Nova Lane",
            albumTitle: "Glass Coast",
            playCount: 7,
            albumPersistentID: 42,
            artistPersistentID: 100
        )

        let albums = MediaLibraryManager.debugAlbumsDerivedFromSongs([firstTrack, secondTrack])

        XCTAssertEqual(albums.first?.artist, "Nova Lane")
        XCTAssertEqual(albums.first?.artistPersistentID, 100)
    }

    func testLibraryPresentationCacheRoundTripsLightweightSongMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountPresentationCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LibraryPresentationCache(directoryURL: directory)
        let capturedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let source = song(
            id: 42,
            title: "Cached Song",
            artist: "Nova Lane",
            albumArtist: "Nova Lane",
            albumTitle: "Glass Coast",
            playCount: 18,
            totalPlayDuration: 4_320,
            lastPlayedDate: capturedAt.addingTimeInterval(-60),
            albumPersistentID: 84,
            artistPersistentID: 126,
            discNumber: 2,
            trackNumber: 7,
            playbackStoreID: "catalog-42"
        )

        cache.save(songs: [source], capturedAt: capturedAt)
        let loaded = try XCTUnwrap(cache.load())

        XCTAssertEqual(loaded.capturedAt, capturedAt)
        XCTAssertEqual(loaded.songs.map(\.id), [42])
        XCTAssertEqual(loaded.songs.first?.title, "Cached Song")
        XCTAssertEqual(loaded.songs.first?.playCount, 18)
        XCTAssertEqual(loaded.songs.first?.totalPlayDuration, 4_320)
        XCTAssertEqual(loaded.songs.first?.discNumber, 2)
        XCTAssertEqual(loaded.songs.first?.trackNumber, 7)
        XCTAssertEqual(loaded.songs.first?.playbackStoreID, "catalog-42")
        XCTAssertNil(loaded.songs.first?.artwork)
        XCTAssertNotNil(cache.load(maximumAge: 60, now: capturedAt.addingTimeInterval(59)))
        XCTAssertNil(cache.load(maximumAge: 60, now: capturedAt.addingTimeInterval(61)))

        let replacement = song(id: 43, title: "Rejected Song", artist: "Nova Lane", playCount: 20)
        cache.save(songs: [replacement], shouldCommit: { false })
        XCTAssertEqual(cache.load()?.songs.map(\.id), [42])

        cache.save(songs: [])
        XCTAssertNil(cache.load())
    }

    func testAuthorizationRevocationClearsVisibleAndCachedLibraryMetadata() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlayCountRevocationCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = LibraryPresentationCache(directoryURL: directory)
        let storedSong = song(id: 42, title: "Private Song", artist: "Nova Lane", playCount: 18)
        cache.save(songs: [storedSong])
        let manager = MediaLibraryManager(
            presentationCache: cache,
            recapCloudSyncService: nil,
            startsAutomatically: false
        )
        manager.debugLoadLibraryFixture(songs: [storedSong], albums: [], artists: [])

        XCTAssertFalse(manager.debugRevalidateAuthorizationStatus(.denied))

        XCTAssertTrue(manager.topSongs.isEmpty)
        XCTAssertTrue(manager.librarySongs.isEmpty)
        XCTAssertFalse(manager.hasLoadedInitialSnapshot)
        XCTAssertNil(cache.load())
    }

    func testPlaybackRefreshDelayKeepsTrailingEdgeForShortSession() {
        let lastRefresh = Date(timeIntervalSince1970: 1_750_000_000)
        let stoppedAt = lastRefresh.addingTimeInterval(180)

        XCTAssertEqual(
            MediaLibraryManager.playbackRefreshDelay(
                now: stoppedAt,
                lastRefresh: lastRefresh,
                interval: 300
            ),
            120,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MediaLibraryManager.playbackRefreshDelay(
                now: lastRefresh.addingTimeInterval(301),
                lastRefresh: lastRefresh,
                interval: 300
            ),
            0,
            accuracy: 0.001
        )
    }

    @MainActor
    func testTrailingPlaybackRefreshReschedulesAndFiresExactlyOnce() async {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        let startedAt = Date()
        var executionDates: [Date] = []

        manager.debugTriggerThrottledPlaybackRefresh(after: 0.03) {
            executionDates.append(Date())
        }
        manager.debugTriggerThrottledPlaybackRefresh(after: 0.07) {
            executionDates.append(Date())
        }

        try? await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(executionDates.count, 1)
        guard let executionDate = executionDates.first else {
            XCTFail("Expected the trailing playback refresh to execute")
            return
        }
        XCTAssertGreaterThanOrEqual(
            executionDate.timeIntervalSince(startedAt),
            0.05
        )
    }

    func testShortcutInvalidationClearsPersistedFingerprint() {
        UserDefaults.standard.set("stale", forKey: PlayCountShortcutParameterRefresh.fingerprintKey)

        PlayCountShortcutParameterRefresh.invalidate()

        XCTAssertNil(UserDefaults.standard.string(forKey: PlayCountShortcutParameterRefresh.fingerprintKey))
    }

    func testYearlyPlayedSongCountIncludesSyncedTopNewSongsOutsideTopSongCap() {
        let sourceStore = makeStore(named: "yearly-source")
        let targetStore = makeStore(named: "yearly-target")
        let baselineDate = date(year: 2026, month: 5, day: 1)
        let latestDate = date(year: 2026, month: 5, day: 8)
        let newSongDate = date(year: 2026, month: 5, day: 7)
        let baselineSongs = (1...260).map {
            song(id: UInt64($0), title: "Existing Song \($0)", artist: "Artist", playCount: 10, artistPersistentID: 20)
        }
        var latestSongs = baselineSongs.map {
            song(id: $0.id, title: $0.title, artist: $0.artist, playCount: $0.playCount + 1, artistPersistentID: $0.artistPersistentID)
        }
        latestSongs.append(
            song(
                id: 9_001,
                title: "Low Delta New Song",
                artist: "Artist",
                playCount: 1,
                dateAdded: newSongDate,
                artistPersistentID: 20
            )
        )

        _ = sourceStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = sourceStore.record(songs: latestSongs, at: latestDate, reason: .foreground)
        XCTAssertTrue(targetStore.mergeSyncPayloads(sourceStore.localSyncPayloads(), now: latestDate))

        let manager = MediaLibraryManager(
            snapshotStore: targetStore,
            recapCloudSyncService: nil,
            startsAutomatically: false
        )
        // Production publishes this asynchronously; view getters no longer
        // synchronously load storage while a migration might hold its queue.
        manager.seedRecapCaches(from: targetStore.cachedRecapPresentation(through: latestDate))
        let yearlyRecap = manager.yearlyRecap(for: 2026)

        XCTAssertEqual(yearlyRecap.topSongs.count, 250)
        XCTAssertEqual(yearlyRecap.topNewSongs.first?.title, "Low Delta New Song")
        XCTAssertEqual(yearlyRecap.playedSongCount, 261)
    }

    func testYearlyRecapAggregatesAlbumAndArtistGainers() {
        let january = date(year: 2026, month: 1, day: 1)
        let february = date(year: 2026, month: 2, day: 1)
        let climbingAlbumJanuary = MonthlyRecap.MovementGroup(
            id: "10", title: "Shared Title", subtitle: "Artist A",
            playDelta: 12, rankChange: 5, currentRank: 8, previousRank: 13, artwork: nil
        )
        let climbingAlbumFebruary = MonthlyRecap.MovementGroup(
            id: "99", title: "shared title", subtitle: "artist a",
            playDelta: 18, rankChange: 9, currentRank: 4, previousRank: 13, artwork: nil
        )
        let distinctAlbum = MonthlyRecap.MovementGroup(
            id: "11", title: "Shared Title", subtitle: "Artist B",
            playDelta: 8, rankChange: 4, currentRank: 12, previousRank: 16, artwork: nil
        )
        let artistJanuary = MonthlyRecap.MovementGroup(
            id: "20", title: "Climbing Artist", subtitle: "Artist",
            playDelta: 20, rankChange: 6, currentRank: 7, previousRank: 13, artwork: nil
        )
        let artistFebruary = MonthlyRecap.MovementGroup(
            id: "21", title: "climbing artist", subtitle: "Artist",
            playDelta: 25, rankChange: 11, currentRank: 2, previousRank: 13, artwork: nil
        )

        func recap(
            month: Date,
            albums: [MonthlyRecap.MovementGroup],
            artists: [MonthlyRecap.MovementGroup]
        ) -> MonthlyRecap {
            MonthlyRecap(
                monthStart: month,
                generatedAt: month,
                lastCaptureReason: .foreground,
                trackingStart: month,
                snapshotCount: 2,
                totalPlayDelta: 0,
                totalSkipDelta: 0,
                totalListeningDuration: 0,
                playedSongCount: 0,
                newSongCount: 0,
                topSongs: [],
                topArtists: [],
                topAlbums: [],
                biggestGainers: [],
                biggestAlbumGainers: albums,
                biggestArtistGainers: artists,
                topNewSongs: []
            )
        }

        let januaryRecap = recap(month: january, albums: [climbingAlbumJanuary, distinctAlbum], artists: [artistJanuary])
        let februaryRecap = recap(month: february, albums: [climbingAlbumFebruary], artists: [artistFebruary])
        let yearly = MonthlyRecap.yearly(
            for: 2026,
            months: [january, february],
            monthlyRecaps: [januaryRecap, februaryRecap],
            fallbackMonth: january,
            fallbackRecap: januaryRecap
        )

        XCTAssertEqual(yearly.biggestAlbumGainers.count, 2)
        XCTAssertEqual(yearly.biggestAlbumGainers.first?.playDelta, 30)
        XCTAssertEqual(yearly.biggestAlbumGainers.first?.rankChange, 9)
        XCTAssertEqual(yearly.biggestAlbumGainers.first?.id, "99")
        XCTAssertEqual(yearly.biggestArtistGainers.count, 1)
        XCTAssertEqual(yearly.biggestArtistGainers.first?.playDelta, 45)
        XCTAssertEqual(yearly.biggestArtistGainers.first?.rankChange, 11)
        XCTAssertEqual(yearly.biggestArtistGainers.first?.id, "21")
    }

    func testAlbumSongOrderSupportsTracklistAndMostPlayed() {
        let discTwo = song(
            id: 1,
            title: "Encore",
            artist: "Artist",
            playCount: 80,
            discNumber: 2,
            trackNumber: 1
        )
        let opener = song(
            id: 2,
            title: "Opening",
            artist: "Artist",
            playCount: 10,
            discNumber: 1,
            trackNumber: 1
        )
        let second = song(
            id: 3,
            title: "Second",
            artist: "Artist",
            playCount: 40,
            discNumber: 1,
            trackNumber: 2
        )

        XCTAssertEqual(AlbumSongOrder.tracklist.sorted([discTwo, second, opener]).map(\.id), [2, 3, 1])
        XCTAssertEqual(AlbumSongOrder.mostPlayed.sorted([opener, second, discTwo]).map(\.id), [1, 3, 2])
    }

    private func manager(
        songs: [TopSong],
        albums: [TopAlbum],
        artists: [TopArtist]
    ) -> MediaLibraryManager {
        let manager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        manager.debugLoadLibraryFixture(songs: songs, albums: albums, artists: artists)
        return manager
    }

    private func makeStore(named name: String) -> MonthlyRecapSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountManagerIndexTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        return MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: name
        )
    }

    private func song(
        id: UInt64,
        title: String,
        artist: String,
        albumArtist: String? = nil,
        albumTitle: String = "Album",
        playCount: Int,
        totalPlayDuration: TimeInterval? = nil,
        lastPlayedDate: Date? = nil,
        dateAdded: Date? = nil,
        albumPersistentID: UInt64 = 1,
        artistPersistentID: UInt64 = 0,
        discNumber: Int = 0,
        trackNumber: Int = 1,
        playbackStoreID: String = ""
    ) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            albumArtist: albumArtist ?? artist,
            playCount: playCount,
            skipCount: 0,
            totalPlayDuration: totalPlayDuration ?? TimeInterval(playCount * 180),
            playbackDuration: 180,
            lastPlayedDate: lastPlayedDate,
            dateAdded: dateAdded,
            artwork: nil,
            albumPersistentID: albumPersistentID,
            artistPersistentID: artistPersistentID,
            discNumber: discNumber,
            trackNumber: trackNumber,
            playbackStoreID: playbackStoreID
        )
    }

    private func album(
        id: UInt64,
        title: String,
        artist: String,
        playCount: Int,
        totalPlayDuration: TimeInterval? = nil,
        artistPersistentID: UInt64
    ) -> TopAlbum {
        TopAlbum(
            id: id,
            title: title,
            artist: artist,
            playCount: playCount,
            totalPlayDuration: totalPlayDuration ?? TimeInterval(playCount * 180),
            artwork: nil,
            artistPersistentID: artistPersistentID
        )
    }

    private func artist(
        id: UInt64,
        name: String,
        playCount: Int = 0,
        totalPlayDuration: TimeInterval = 0
    ) -> TopArtist {
        TopArtist(
            id: id,
            name: name,
            playCount: playCount,
            totalPlayDuration: totalPlayDuration,
            artwork: nil
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        ).date!
    }
}
