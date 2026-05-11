import XCTest
@testable import PlayCount

final class MonthlyRecapSnapshotStoreTests: XCTestCase {
    func testRecapPayloadRoundTripMergesIntoFreshStore() {
        let sourceStore = makeStore(named: "source")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let latestDate = date(year: 2026, month: 5, day: 5, hour: 12)

        _ = sourceStore.record(
            songs: [song(id: 1, title: "First", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        let sourceRecap = sourceStore.record(
            songs: [song(id: 1, title: "First", playCount: 14)],
            at: latestDate,
            reason: .foreground
        )

        XCTAssertEqual(sourceRecap.totalPlayDelta, 4)
        XCTAssertEqual(sourceRecap.topSongs.first?.title, "First")

        let payloads = sourceStore.syncPayloads()
        XCTAssertEqual(payloads.count, 2)

        let targetStore = makeStore(named: "target")
        XCTAssertTrue(targetStore.mergeSyncPayloads(payloads, now: latestDate))

        let targetRecap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(targetRecap.totalPlayDelta, sourceRecap.totalPlayDelta)
        XCTAssertEqual(targetRecap.topSongs.first?.playDelta, 4)
    }

    func testSyncedRecapSummaryKeepsRankedListsConsistentAcrossDevices() {
        let phoneStore = makeStore(named: "summary-phone")
        let iPadStore = makeStore(named: "summary-ipad")
        let baselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)

        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 10),
                song(id: 2, title: "Phone Runner Up", playCount: 20)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 17),
                song(id: 2, title: "Phone Runner Up", playCount: 25)
            ],
            at: latestDate,
            reason: .foreground
        )

        _ = iPadStore.record(
            songs: [song(id: 3, title: "iPad Local", playCount: 30)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 3, title: "iPad Local", playCount: 42)],
            at: latestDate,
            reason: .foreground
        )

        let phonePayloads = phoneStore.localSyncPayloads()
        XCTAssertFalse(phonePayloads.isEmpty)
        XCTAssertTrue(phonePayloads.allSatisfy { $0.encodedRecaps != nil })
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phonePayloads, now: latestDate))

        let recap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 12)
        XCTAssertEqual(recap.playedSongCount, 2)
        XCTAssertEqual(recap.topSongs.map(\.title), ["Phone Favorite", "Phone Runner Up"])
    }

    func testSyncedRecapSummaryWinsWhenLocalDeviceHasDifferentEqualQualityRankings() {
        let phoneStore = makeStore(named: "equal-summary-phone")
        let iPadStore = makeStore(named: "equal-summary-ipad")
        let baselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let phoneLatestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let iPadLatestDate = date(year: 2026, month: 5, day: 8, hour: 9)

        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 10),
                song(id: 2, title: "Phone Runner Up", playCount: 20)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [
                song(id: 1, title: "Phone Favorite", playCount: 17),
                song(id: 2, title: "Phone Runner Up", playCount: 25)
            ],
            at: phoneLatestDate,
            reason: .foreground
        )

        _ = iPadStore.record(
            songs: [
                song(id: 3, title: "iPad Favorite", playCount: 30),
                song(id: 4, title: "iPad Runner Up", playCount: 40)
            ],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [
                song(id: 3, title: "iPad Favorite", playCount: 37),
                song(id: 4, title: "iPad Runner Up", playCount: 45)
            ],
            at: iPadLatestDate,
            reason: .foreground
        )

        XCTAssertEqual(iPadStore.recap(forMonthContaining: iPadLatestDate).topSongs.first?.title, "iPad Favorite")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phoneStore.localSyncPayloads(), now: iPadLatestDate))

        let recap = iPadStore.recap(forMonthContaining: iPadLatestDate)
        XCTAssertEqual(recap.totalPlayDelta, 12)
        XCTAssertEqual(recap.playedSongCount, 2)
        XCTAssertEqual(recap.topSongs.map(\.title), ["Phone Favorite", "Phone Runner Up"])
    }

    func testSyncedPhoneRecapWinsOverLaterEmptyLocalDeviceSnapshot() {
        let phoneStore = makeStore(named: "phone")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let phoneLatestDate = date(year: 2026, month: 5, day: 5, hour: 12)
        let iPadLaterDate = date(year: 2026, month: 5, day: 5, hour: 13)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 14)],
            at: phoneLatestDate,
            reason: .foreground
        )

        let iPadStore = makeStore(named: "ipad")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phoneStore.syncPayloads(), now: iPadLaterDate))
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Local Empty Baseline", playCount: 0)],
            at: iPadLaterDate,
            reason: .foreground
        )

        let recap = iPadStore.recap(forMonthContaining: iPadLaterDate)
        XCTAssertEqual(recap.totalPlayDelta, 4)
        XCTAssertEqual(recap.topSongs.first?.title, "Phone Song")
    }

    func testEstablishedPhoneStreamWinsOverLaterInflatedDeviceStream() {
        let phoneStore = makeStore(named: "phone-established")
        let iPadStore = makeStore(named: "ipad-inflated")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let phoneLatestDate = date(year: 2026, month: 5, day: 5, hour: 12)
        let iPadBaselineDate = date(year: 2026, month: 5, day: 6, hour: 10)
        let iPadLatestDate = date(year: 2026, month: 5, day: 6, hour: 11)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Phone Song", playCount: 14)],
            at: phoneLatestDate,
            reason: .foreground
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Inflated iPad Song", playCount: 1)],
            at: iPadBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Inflated iPad Song", playCount: 10_000)],
            at: iPadLatestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-established")
        XCTAssertTrue(targetStore.mergeSyncPayloads(phoneStore.syncPayloads() + iPadStore.syncPayloads(), now: iPadLatestDate))

        let recap = targetStore.recap(forMonthContaining: iPadLatestDate)
        XCTAssertEqual(recap.totalPlayDelta, 4)
        XCTAssertEqual(recap.topSongs.first?.title, "Phone Song")
    }

    func testPartialBaselineDoesNotInflateLaterFullLibrarySnapshot() {
        let store = makeStore(named: "partial-baseline")
        let partialDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let fullDate = date(year: 2026, month: 5, day: 1, hour: 10)
        let fullSongs = (1...1_000).map {
            song(id: UInt64($0), title: "Song \($0)", playCount: 100)
        }

        _ = store.record(
            songs: [song(id: 1, title: "Song 1", playCount: 1)],
            at: partialDate,
            reason: .appLaunch
        )
        _ = store.record(
            songs: fullSongs,
            at: fullDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: fullDate)
        XCTAssertEqual(recap.totalPlayDelta, 0)
        XCTAssertTrue(recap.topSongs.isEmpty)
    }

    func testImplausibleLocalStreamDoesNotOverridePlausibleRemoteRecap() {
        let phoneStore = makeStore(named: "phone-plausible")
        let iPadStore = makeStore(named: "ipad-implausible")
        let iPadBaselineDate = date(year: 2026, month: 5, day: 1, hour: 0)
        let phoneBaselineDate = date(year: 2026, month: 5, day: 2, hour: 0)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 0)

        _ = iPadStore.record(
            songs: [song(id: 1, title: "Polluted iPad Song", playCount: 0)],
            at: iPadBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 1, title: "Polluted iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )
        _ = phoneStore.record(
            songs: [song(id: 2, title: "Real Phone Song", playCount: 100)],
            at: phoneBaselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 2, title: "Real Phone Song", playCount: 433)],
            at: latestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-plausible")
        XCTAssertTrue(targetStore.mergeSyncPayloads(iPadStore.syncPayloads() + phoneStore.syncPayloads(), now: latestDate))

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 333)
        XCTAssertEqual(Int(recap.totalListeningDuration / 60), 999)
        XCTAssertEqual(recap.topSongs.first?.title, "Real Phone Song")
    }

    func testLateRemoteBaselineCanStillRepresentMonthToDateRecap() {
        let phoneStore = makeStore(named: "phone-late-baseline")
        let iPadStore = makeStore(named: "ipad-inflated-late-baseline")
        let monthStart = date(year: 2026, month: 5, day: 1, hour: 0)
        let baselineDate = date(year: 2026, month: 5, day: 8, hour: 10)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 11)

        _ = phoneStore.record(
            songs: [song(id: 1, title: "Real Phone Song", playCount: 100)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: [song(id: 1, title: "Real Phone Song", playCount: 433)],
            at: latestDate,
            reason: .foreground
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Polluted iPad Song", playCount: 0)],
            at: monthStart,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 2, title: "Polluted iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-late-baseline")
        XCTAssertTrue(targetStore.mergeSyncPayloads(iPadStore.syncPayloads() + phoneStore.syncPayloads(), now: latestDate))

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 333)
        XCTAssertEqual(Int(recap.totalListeningDuration / 60), 999)
        XCTAssertEqual(recap.topSongs.first?.title, "Real Phone Song")
    }

    func testReliableRankingStreamWinsOverAggregateOnlyStream() {
        let reliableStore = makeStore(named: "reliable-ranking")
        let aggregateOnlyStore = makeStore(named: "aggregate-only-ranking")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)

        _ = aggregateOnlyStore.record(
            songs: [song(id: 1, title: "Old Identity", playCount: 1_000)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = aggregateOnlyStore.record(
            songs: [song(id: 2, title: "New Identity", playCount: 1_300)],
            at: latestDate,
            reason: .foreground
        )

        _ = reliableStore.record(
            songs: [song(id: 3, title: "Reliable Song", playCount: 10)],
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = reliableStore.record(
            songs: [song(id: 3, title: "Reliable Song", playCount: 14)],
            at: latestDate,
            reason: .foreground
        )

        let targetStore = makeStore(named: "target-ranking-coverage")
        XCTAssertTrue(targetStore.mergeSyncPayloads(
            aggregateOnlyStore.syncPayloads() + reliableStore.syncPayloads(),
            now: latestDate
        ))

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.topSongs.first?.title, "Reliable Song")
        XCTAssertEqual(recap.totalPlayDelta, 4)
    }

    func testTrimmedSyncPayloadPreservesFullAggregateTotals() {
        let phoneStore = makeStore(named: "phone-large")
        let baselineDate = date(year: 2026, month: 4, day: 30, hour: 23)
        let latestDate = date(year: 2026, month: 5, day: 5, hour: 12)
        let largeSuffix = String(repeating: "x", count: 1_000)
        let baselineSongs = (1...1_200).map {
            song(id: UInt64($0), title: "Song \($0) \(largeSuffix)", playCount: 10)
        }
        let latestSongs = (1...1_200).map {
            song(id: UInt64($0), title: "Song \($0) \(largeSuffix)", playCount: 11)
        }

        _ = phoneStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        let sourceRecap = phoneStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = phoneStore.localSyncPayloads()
        XCTAssertLessThanOrEqual(payloads.map(\.encodedSnapshot.count).max() ?? 0, 250_000)

        let iPadStore = makeStore(named: "ipad-large")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(payloads, now: latestDate))

        let iPadRecap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(sourceRecap.totalPlayDelta, 1_200)
        XCTAssertEqual(iPadRecap.totalPlayDelta, sourceRecap.totalPlayDelta)
        XCTAssertEqual(iPadRecap.totalListeningDuration, sourceRecap.totalListeningDuration)
        XCTAssertEqual(iPadRecap.playedSongCount, sourceRecap.playedSongCount)
        XCTAssertLessThan(iPadRecap.topSongs.count, baselineSongs.count)
    }

    func testHigherUserRecapTotalsWinOverLaterLowerDeviceBaseline() {
        let phoneStore = makeStore(named: "phone-synced-source")
        let iPadStore = makeStore(named: "ipad-user-source")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let phoneLatestDate = date(year: 2026, month: 5, day: 10, hour: 6)
        let iPadBaselineDate = date(year: 2026, month: 5, day: 8, hour: 21)
        let iPadLatestDate = date(year: 2026, month: 5, day: 10, hour: 6)
        let largeSuffix = String(repeating: "x", count: 1_000)
        let phoneBaselineSongs = (1...1_200).map {
            song(id: UInt64($0), title: "Phone Song \($0) \(largeSuffix)", playCount: 100)
        }
        let phoneLatestSongs = phoneBaselineSongs.enumerated().map { index, baselineSong in
            let extraPlay = index < 379 ? 1 : 0
            return song(
                id: baselineSong.id,
                title: baselineSong.title,
                playCount: baselineSong.playCount + extraPlay
            )
        }
        let iPadBaselineSongs = (1...1_200).map {
            song(id: UInt64(10_000 + $0), title: "iPad Song \($0)", playCount: 100)
        }
        let iPadLatestSongs = iPadBaselineSongs.enumerated().map { index, baselineSong in
            let extraPlay = index < 65 ? 1 : 0
            return song(
                id: baselineSong.id,
                title: baselineSong.title,
                playCount: baselineSong.playCount + extraPlay
            )
        }

        _ = phoneStore.record(songs: phoneBaselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = phoneStore.record(songs: phoneLatestSongs, at: phoneLatestDate, reason: .foreground)
        XCTAssertTrue(iPadStore.mergeSyncPayloads(phoneStore.localSyncPayloads(), now: phoneLatestDate))
        _ = iPadStore.record(songs: iPadBaselineSongs, at: iPadBaselineDate, reason: .manualRefresh)
        _ = iPadStore.record(songs: iPadLatestSongs, at: iPadLatestDate, reason: .foreground)

        let recap = iPadStore.recap(forMonthContaining: iPadLatestDate)
        XCTAssertEqual(recap.totalPlayDelta, 379)
    }

    func testTrimmedLocalSyncPayloadPreservesChangedSongRankings() {
        let phoneStore = makeStore(named: "phone-large-ranking")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let largeSuffix = String(repeating: "x", count: 1_000)
        var baselineSongs: [TopSong] = []
        for index in 1...1_200 {
            let isRecentFavorite = index == 1_200
            let title = isRecentFavorite ? "Actual Recent Favorite \(largeSuffix)" : "Song \(index) \(largeSuffix)"
            let playCount = isRecentFavorite ? 0 : 1_000 - min(index, 999)
            baselineSongs.append(song(id: UInt64(index), title: title, playCount: playCount))
        }
        let latestSongs = baselineSongs.map { baselineSong -> TopSong in
            guard baselineSong.id == 1_200 else { return baselineSong }
            return song(id: baselineSong.id, title: baselineSong.title, playCount: 25)
        }

        _ = phoneStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = phoneStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = phoneStore.localSyncPayloads()
        XCTAssertLessThanOrEqual(payloads.map(\.encodedSnapshot.count).max() ?? 0, 250_000)

        let iPadStore = makeStore(named: "ipad-large-ranking")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(payloads, now: latestDate))

        let iPadRecap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(iPadRecap.totalPlayDelta, 25)
        XCTAssertEqual(iPadRecap.topSongs.first?.title, "Actual Recent Favorite \(largeSuffix)")
    }

    func testTrimmedLocalSyncPayloadPreservesNewSongRankings() {
        let phoneStore = makeStore(named: "phone-new-ranking")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let newSongDate = date(year: 2026, month: 5, day: 7, hour: 8)
        let largeSuffix = String(repeating: "x", count: 1_000)
        var baselineSongs: [TopSong] = []
        for index in 1...1_200 {
            baselineSongs.append(
                song(
                    id: UInt64(index),
                    title: "Catalog Song \(index) \(largeSuffix)",
                    playCount: 1_000 - min(index, 999)
                )
            )
        }
        var latestSongs = baselineSongs
        latestSongs.append(
            song(
                id: 9_001,
                title: "Sabrina New Song \(largeSuffix)",
                playCount: 12,
                dateAdded: newSongDate
            )
        )

        _ = phoneStore.record(songs: baselineSongs, at: baselineDate, reason: .manualRefresh)
        _ = phoneStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let payloads = phoneStore.localSyncPayloads()
        XCTAssertLessThanOrEqual(payloads.map(\.encodedSnapshot.count).max() ?? 0, 250_000)

        let iPadStore = makeStore(named: "ipad-new-ranking")
        XCTAssertTrue(iPadStore.mergeSyncPayloads(payloads, now: latestDate))

        let iPadRecap = iPadStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(iPadRecap.topNewSongs.first?.title, "Sabrina New Song \(largeSuffix)")
        XCTAssertEqual(iPadRecap.topNewSongs.first?.playDelta, 12)
    }

    func testLegacyPhoneBaselineBridgesToCurrentPhoneStreamForConsistentRecap() {
        let phoneStore = makeStore(named: "current-phone")
        let iPadStore = makeStore(named: "polluted-ipad")
        let targetStore = makeStore(named: "target-consistent")
        let legacyBaselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let currentPhoneBaselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let sabrinaDate = date(year: 2026, month: 5, day: 6, hour: 8)

        let legacyBaseline = recapFixtureSongs(
            climberPlayCount: 10,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let currentPhoneBaseline = recapFixtureSongs(
            climberPlayCount: 25,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        var latestPhoneSongs = recapFixtureSongs(
            climberPlayCount: 45,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        latestPhoneSongs.append(song(
            id: 9_001,
            title: "Sabrina New Song",
            playCount: 12,
            dateAdded: sabrinaDate
        ))

        _ = phoneStore.debugRecordLegacySnapshot(
            songs: legacyBaseline,
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: currentPhoneBaseline,
            at: currentPhoneBaselineDate,
            reason: .foreground
        )
        let phoneRecap = phoneStore.record(
            songs: latestPhoneSongs,
            at: latestDate,
            reason: .foreground
        )

        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 0)],
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )

        XCTAssertEqual(phoneRecap.totalPlayDelta, 47)
        XCTAssertEqual(phoneRecap.topNewSongs.first?.title, "Sabrina New Song")
        XCTAssertEqual(phoneRecap.biggestGainers.first?.title, "Climber")

        XCTAssertTrue(targetStore.mergeSyncPayloads(
            iPadStore.syncPayloads() + phoneStore.localSyncPayloads(),
            now: latestDate
        ))

        let targetRecap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(targetRecap.totalPlayDelta, phoneRecap.totalPlayDelta)
        XCTAssertEqual(targetRecap.totalListeningDuration, phoneRecap.totalListeningDuration)
        XCTAssertEqual(targetRecap.topSongs.map(\.title), phoneRecap.topSongs.map(\.title))
        XCTAssertEqual(targetRecap.biggestGainers.map(\.title), phoneRecap.biggestGainers.map(\.title))
        XCTAssertEqual(targetRecap.topNewSongs.map(\.title), phoneRecap.topNewSongs.map(\.title))
    }

    func testCanonicalRecapIsIndependentOfPayloadMergeOrder() {
        let phoneStore = makeStore(named: "phone-order")
        let iPadStore = makeStore(named: "ipad-order")
        let firstTargetStore = makeStore(named: "target-order-first")
        let secondTargetStore = makeStore(named: "target-order-second")
        let legacyBaselineDate = date(year: 2026, month: 5, day: 1, hour: 8)
        let currentPhoneBaselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let sabrinaDate = date(year: 2026, month: 5, day: 6, hour: 8)

        _ = phoneStore.debugRecordLegacySnapshot(
            songs: recapFixtureSongs(
                climberPlayCount: 10,
                otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
            ),
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = phoneStore.record(
            songs: recapFixtureSongs(
                climberPlayCount: 25,
                otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
            ),
            at: currentPhoneBaselineDate,
            reason: .foreground
        )
        var latestPhoneSongs = recapFixtureSongs(
            climberPlayCount: 45,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        latestPhoneSongs.append(song(
            id: 9_001,
            title: "Sabrina New Song",
            playCount: 12,
            dateAdded: sabrinaDate
        ))
        _ = phoneStore.record(songs: latestPhoneSongs, at: latestDate, reason: .foreground)

        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 0)],
            at: legacyBaselineDate,
            reason: .manualRefresh
        )
        _ = iPadStore.record(
            songs: [song(id: 50_001, title: "Inflated iPad Song", playCount: 9_000)],
            at: latestDate,
            reason: .foreground
        )

        let phonePayloads = phoneStore.localSyncPayloads()
        let iPadPayloads = iPadStore.syncPayloads()
        XCTAssertTrue(firstTargetStore.mergeSyncPayloads(phonePayloads + iPadPayloads, now: latestDate))
        XCTAssertTrue(secondTargetStore.mergeSyncPayloads(iPadPayloads + phonePayloads, now: latestDate))

        let firstRecap = firstTargetStore.recap(forMonthContaining: latestDate)
        let secondRecap = secondTargetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(firstRecap, secondRecap)
        XCTAssertEqual(firstRecap.totalPlayDelta, 47)
        XCTAssertEqual(firstRecap.topNewSongs.first?.title, "Sabrina New Song")
        XCTAssertEqual(firstRecap.biggestGainers.first?.title, "Climber")
    }

    func testDuplicateTrimmedBaselineDoesNotOverrideFullBaselineCopy() {
        let targetStore = makeStore(named: "full-plus-trimmed-target")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let baselineSongs = recapFixtureSongs(
            climberPlayCount: 1,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let trimmedBaselineSongs = Array(baselineSongs.prefix(5))
        let latestSongs = baselineSongs.map { baselineSong -> TopSong in
            guard baselineSong.id == 100 else { return baselineSong }
            return song(id: baselineSong.id, title: baselineSong.title, playCount: 85)
        }

        _ = targetStore.debugRecordLegacySnapshot(
            songs: baselineSongs,
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = targetStore.debugRecordLegacySnapshot(
            songs: trimmedBaselineSongs,
            at: baselineDate,
            reason: .manualRefresh,
            scannedSongCount: baselineSongs.count,
            aggregateSongs: baselineSongs
        )
        _ = targetStore.record(songs: latestSongs, at: latestDate, reason: .foreground)

        let recap = targetStore.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.topSongs.first?.title, "Climber")
        XCTAssertEqual(recap.topSongs.first?.playDelta, 84)
        XCTAssertEqual(recap.biggestGainers.first?.title, "Climber")
    }

    func testLocalSyncPayloadsCanonicalizeDuplicateSnapshotMoments() {
        let store = makeStore(named: "canonical-local-sync")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let baselineSongs = recapFixtureSongs(
            climberPlayCount: 1,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let trimmedBaselineSongs = Array(baselineSongs.prefix(5))
        let latestSongs = baselineSongs.map { baselineSong -> TopSong in
            guard baselineSong.id == 100 else { return baselineSong }
            return song(id: baselineSong.id, title: baselineSong.title, playCount: 85)
        }

        _ = store.debugRecordLegacySnapshot(
            songs: baselineSongs,
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = store.debugRecordLegacySnapshot(
            songs: trimmedBaselineSongs,
            at: baselineDate,
            reason: .manualRefresh,
            scannedSongCount: baselineSongs.count,
            aggregateSongs: baselineSongs
        )
        _ = store.record(songs: latestSongs, at: latestDate, reason: .foreground)

        XCTAssertEqual(store.localSyncPayloads().count, 2)
    }

    func testMergeSyncPayloadsCanonicalizesDuplicateSnapshotMoments() {
        let fullSourceStore = makeStore(named: "full-source")
        let trimmedSourceStore = makeStore(named: "trimmed-source")
        let targetStore = makeStore(named: "canonical-merge-target")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let baselineSongs = recapFixtureSongs(
            climberPlayCount: 1,
            otherPlayCounts: [100, 92, 84, 76, 68, 60, 52, 44, 36, 28]
        )
        let trimmedBaselineSongs = Array(baselineSongs.prefix(5))

        _ = fullSourceStore.record(
            songs: baselineSongs,
            at: baselineDate,
            reason: .manualRefresh
        )
        _ = trimmedSourceStore.debugRecordLegacySnapshot(
            songs: trimmedBaselineSongs,
            at: baselineDate,
            reason: .manualRefresh,
            scannedSongCount: baselineSongs.count,
            aggregateSongs: baselineSongs
        )

        XCTAssertTrue(targetStore.mergeSyncPayloads(
            fullSourceStore.syncPayloads() + trimmedSourceStore.syncPayloads(),
            now: baselineDate
        ))
        XCTAssertEqual(targetStore.syncPayloads().count, 1)
    }

    func testNoisyExistingCounterChurnDoesNotDominateRankings() {
        let store = makeStore(named: "noisy-existing-deltas")
        let baselineDate = date(year: 2026, month: 5, day: 5, hour: 8)
        let latestDate = date(year: 2026, month: 5, day: 8, hour: 8)
        let newSongDate = date(year: 2026, month: 5, day: 6, hour: 8)
        let fillerSongs = (4...22).map { index in
            song(id: UInt64(index), title: "Stable Catalog Song \(index)", playCount: 1)
        }

        _ = store.record(
            songs: [
                song(id: 1, title: "Counter Churn Song", playCount: 100),
                song(id: 2, title: "Counter Drop Song", playCount: 500)
            ] + fillerSongs,
            at: baselineDate,
            reason: .manualRefresh
        )

        _ = store.record(
            songs: [
                song(id: 1, title: "Counter Churn Song", playCount: 300),
                song(id: 2, title: "Counter Drop Song", playCount: 324),
                song(id: 3, title: "Sabrina New Song", playCount: 12, dateAdded: newSongDate)
            ] + fillerSongs,
            at: latestDate,
            reason: .foreground
        )

        let recap = store.recap(forMonthContaining: latestDate)
        XCTAssertEqual(recap.totalPlayDelta, 36)
        XCTAssertEqual(recap.topSongs.first?.title, "Sabrina New Song")
        XCTAssertEqual(recap.topSongs.first?.playDelta, 12)
        XCTAssertEqual(recap.topNewSongs.first?.title, "Sabrina New Song")
        XCTAssertTrue(recap.biggestGainers.isEmpty)
    }

    func testBatchRecapsReuseOneSnapshotLoadPath() {
        let store = makeStore(named: "batch")
        let aprilBaseline = date(year: 2026, month: 4, day: 1)
        let aprilLatest = date(year: 2026, month: 4, day: 15)
        let mayLatest = date(year: 2026, month: 5, day: 3)

        _ = store.record(
            songs: [song(id: 1, title: "April Song", playCount: 3)],
            at: aprilBaseline,
            reason: .manualRefresh
        )
        _ = store.record(
            songs: [song(id: 1, title: "April Song", playCount: 8)],
            at: aprilLatest,
            reason: .foreground
        )
        _ = store.record(
            songs: [song(id: 1, title: "April Song", playCount: 10)],
            at: mayLatest,
            reason: .foreground
        )

        let recaps = store.recaps(forMonthsContaining: [aprilLatest, mayLatest])
        XCTAssertEqual(recaps.map(\.totalPlayDelta), [5, 2])
    }

    private func makeStore(named name: String) -> MonthlyRecapSnapshotStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PlayCountTests-\(UUID().uuidString)-\(name)", isDirectory: true)
        return MonthlyRecapSnapshotStore(
            directoryURL: directory,
            calendar: Calendar(identifier: .gregorian),
            deviceIdentifier: name
        )
    }

    private func song(id: UInt64, title: String, playCount: Int, dateAdded: Date? = nil) -> TopSong {
        TopSong(
            id: id,
            title: title,
            artist: "Artist",
            albumTitle: "Album",
            playCount: playCount,
            skipCount: 0,
            totalPlayDuration: TimeInterval(playCount * 180),
            playbackDuration: 180,
            lastPlayedDate: nil,
            dateAdded: dateAdded,
            artwork: nil,
            albumPersistentID: 10,
            artistPersistentID: 20,
            trackNumber: 1
        )
    }

    private func recapFixtureSongs(climberPlayCount: Int, otherPlayCounts: [Int]) -> [TopSong] {
        var songs = otherPlayCounts.enumerated().map { index, playCount in
            song(id: UInt64(index + 1), title: "Catalog Song \(index + 1)", playCount: playCount)
        }
        songs.append(song(id: 100, title: "Climber", playCount: climberPlayCount))
        return songs
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour
        ).date!
    }
}
