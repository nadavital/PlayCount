import MediaPlayer
import SwiftUI

struct MonthlyRecapView: View {
    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedMonthStart: Date?
    @State private var isShowingYearAggregate = false
    @State private var monthTransitionEdge: Edge = .trailing
    @State private var monthDragOffset: CGFloat = 0
    @State private var monthDragAxis: MonthDragAxis = .undecided
    @State private var isSuppressingRecapNavigation = false
    @State private var recapNavigationSuppressionToken = 0
    @State private var selectedRecapDestination: RecapNavigationDestination?
    @State private var isUsingYearlyBreakdownStrip = false
    @State private var cachedArtworkHighlights: [MPMediaItemArtwork] = []
    @State private var cachedArtworkHighlightsSignature = ""
    @State private var cachedRecapBackgroundPalette: RecapBackgroundPalette?
    @State private var hasScheduledInitialCloudSync = false

    #if DEBUG
    @State private var reminderStatusMessage: String?
    #endif

    private enum MonthDragAxis {
        case undecided
        case horizontal
        case vertical
    }

    private enum RecapNavigationDestination: Hashable {
        case song(id: UInt64, title: String, artist: String)
        case album(id: UInt64, title: String, artist: String)
        case artist(id: UInt64, name: String)
    }

    private var recap: MonthlyRecap {
        if isShowingYearAggregate {
            return manager.yearlyRecap(for: selectedRecapYear)
        }
        return recapForMonth(selectedMonthStartOrCurrent)
    }

    private func recapForMonth(_ month: Date) -> MonthlyRecap {
        if Calendar.current.isDate(month, equalTo: manager.monthlyRecap.monthStart, toGranularity: .month) {
            return manager.monthlyRecap
        }
        return manager.recap(forMonthContaining: month)
    }

    private var selectedMonthStartOrCurrent: Date {
        normalizedMonth(selectedMonthStart ?? manager.monthlyRecap.monthStart)
    }

    private var availableMonthStarts: [Date] {
        let source = manager.availableRecapMonths.isEmpty ? [manager.monthlyRecap.monthStart] : manager.availableRecapMonths
        return Array(Set(source.map(normalizedMonth))).sorted()
    }

    private var selectedMonthIndex: Int? {
        availableMonthStarts.firstIndex {
            Calendar.current.isDate($0, equalTo: selectedMonthStartOrCurrent, toGranularity: .month)
        }
    }

    private var canSelectPreviousMonth: Bool {
        if isShowingYearAggregate {
            guard let selectedYearIndex = availableRecapYears.firstIndex(of: selectedRecapYear) else { return false }
            return selectedYearIndex > 0
        }
        guard let selectedMonthIndex else { return false }
        return selectedMonthIndex > 0 || !selectedYearMonths.isEmpty
    }

    private var canSelectNextMonth: Bool {
        if isShowingYearAggregate {
            return !selectedYearMonths.isEmpty
        }
        guard let selectedMonthIndex else { return false }
        return selectedMonthIndex < availableMonthStarts.count - 1
    }

    private var hasMultipleRecapMonths: Bool {
        availableMonthStarts.count > 1
    }

    private var availableRecapYears: [Int] {
        Array(Set(availableMonthStarts.map { Calendar.current.component(.year, from: $0) })).sorted()
    }

    private var hasMultipleRecapYears: Bool {
        availableRecapYears.count > 1
    }

    private var selectedRecapYear: Int {
        Calendar.current.component(.year, from: selectedMonthStartOrCurrent)
    }

    private var selectedYearMonths: [Date] {
        months(in: selectedRecapYear)
    }

    private func months(in year: Int) -> [Date] {
        let calendar = Calendar.current
        return availableMonthStarts.filter {
            calendar.component(.year, from: $0) == year
        }
    }

    private struct YearlyMonthlyHighlight: Identifiable {
        let month: Date
        let recap: MonthlyRecap

        var id: Date { month }
    }

    private var recapDrilldownContext: RecapDrilldownContext {
        RecapDrilldownContext(
            monthTitle: monthTitle,
            songs: monthlyRankedSongs,
            songSectionTitle: isShowingYearAggregate ? "This Year" : "This Month",
            songsSectionTitle: isShowingYearAggregate ? "Top This Year" : "Top This Month",
            periodBreakdowns: isShowingYearAggregate ? yearlyPeriodBreakdowns : []
        )
    }

    private var monthlyRankedSongs: [MonthlyRecap.RankedSong] {
        rankedSongs(in: recap)
    }

    private var yearlyPeriodBreakdowns: [RecapPeriodBreakdown] {
        yearlyMonthlyHighlights.map { highlight in
            RecapPeriodBreakdown(
                id: "\(highlight.id.timeIntervalSinceReferenceDate)",
                title: Self.yearlyBreakdownMonthFormatter.string(from: highlight.month),
                songs: rankedSongs(in: highlight.recap)
            )
        }
    }

    private func rankedSongs(in recap: MonthlyRecap) -> [MonthlyRecap.RankedSong] {
        var seen: Set<UInt64> = []
        var result: [MonthlyRecap.RankedSong] = []

        func append(_ song: MonthlyRecap.RankedSong) {
            guard !seen.contains(song.id) else { return }
            seen.insert(song.id)
            result.append(song)
        }

        recap.topSongs.forEach(append)
        recap.topNewSongs.forEach(append)

        for movementSong in recap.biggestGainers where !seen.contains(movementSong.id) {
            guard let topSong = resolvedTopSong(for: movementSong) else { continue }
            append(
                MonthlyRecap.RankedSong(
                    id: movementSong.id,
                    title: movementSong.title,
                    artist: movementSong.artist,
                    albumTitle: topSong.albumTitle,
                    playDelta: movementSong.playDelta,
                    skipDelta: 0,
                    listeningDuration: TimeInterval(movementSong.playDelta) * topSong.playbackDuration,
                    artwork: resolvedArtwork(for: movementSong)
                )
            )
        }

        return result
    }

    private var artworkHighlights: [MPMediaItemArtwork] {
        var seen: Set<String> = []
        var result: [MPMediaItemArtwork] = []

        for song in recap.topSongs {
            appendUniqueArtwork(
                key: song.albumTitle.recapAlbumArtworkKey,
                artwork: resolvedArtwork(for: song),
                seen: &seen,
                result: &result
            )
        }

        for song in recap.topNewSongs {
            appendUniqueArtwork(
                key: song.albumTitle.recapAlbumArtworkKey,
                artwork: resolvedArtwork(for: song),
                seen: &seen,
                result: &result
            )
        }

        for song in manager.topSongs {
            let key = song.albumPersistentID == 0 ? song.albumTitle.recapAlbumArtworkKey : "album-id-\(song.albumPersistentID)"
            appendUniqueArtwork(key: key, artwork: song.artwork, seen: &seen, result: &result)
        }

        for album in manager.topAlbums {
            let key = album.id == 0 ? album.title.recapAlbumArtworkKey : "album-id-\(album.id)"
            appendUniqueArtwork(key: key, artwork: album.artwork, seen: &seen, result: &result)
        }

        return result
    }

    private var artworkHighlightsSignature: String {
        let recapSongIDs = (recap.topSongs.prefix(6).map(\.id) + recap.topNewSongs.prefix(6).map(\.id))
            .map { String($0) }
            .joined(separator: ",")
        let libraryAlbumIDs = manager.topAlbums.prefix(6).map { String($0.id) }.joined(separator: ",")
        let librarySongIDs = manager.topSongs.prefix(6).map { String($0.id) }.joined(separator: ",")
        return [
            String(recap.monthStart.timeIntervalSinceReferenceDate),
            String(recap.generatedAt.timeIntervalSinceReferenceDate),
            recapSongIDs,
            librarySongIDs,
            libraryAlbumIDs
        ].joined(separator: "|")
    }

    private var recapBackgroundPalette: RecapBackgroundPalette {
        if let cachedRecapBackgroundPalette {
            return cachedRecapBackgroundPalette
        }

        return RecapBackgroundPalette(seed: recapBackgroundSeed)
    }

    private var recapBackgroundSeed: UInt64 {
        var seed = UInt64(recap.monthStart.timeIntervalSinceReferenceDate.rounded())
        seed = seed &* 1_099_511_628_211 &+ UInt64(max(recap.totalPlayDelta, 0))
        seed = seed &* 1_099_511_628_211 &+ UInt64(recap.playedSongCount)
        for id in recap.topSongs.prefix(3).map(\.id) + recap.topNewSongs.prefix(3).map(\.id) {
            seed = seed &* 1_099_511_628_211 &+ id
        }
        return seed
    }

    private func updateCachedArtworkHighlightsIfNeeded() {
        let signature = artworkHighlightsSignature
        guard signature != cachedArtworkHighlightsSignature || cachedRecapBackgroundPalette == nil else { return }
        let highlights = artworkHighlights
        cachedArtworkHighlights = highlights
        cachedRecapBackgroundPalette = RecapBackgroundPalette(
            artworks: highlights,
            fallbackSeed: recapBackgroundSeed
        )
        cachedArtworkHighlightsSignature = signature
    }

    private func scheduleInitialCloudSyncIfNeeded() {
        guard !hasScheduledInitialCloudSync else { return }
        hasScheduledInitialCloudSync = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            manager.syncRecapFromCloud()
        }
    }

    private func resolvedArtwork(for song: MonthlyRecap.RankedSong) -> MPMediaItemArtwork? {
        song.artwork
            ?? manager.song(withPersistentID: song.id)?.artwork
            ?? manager.song(matchingTitle: song.title, artist: song.artist)?.artwork
            ?? albumArtwork(title: song.albumTitle, artist: song.artist)
    }

    private func resolvedArtwork(for song: MonthlyRecap.MovementSong) -> MPMediaItemArtwork? {
        song.artwork
            ?? manager.song(withPersistentID: song.id)?.artwork
            ?? manager.song(matchingTitle: song.title, artist: song.artist)?.artwork
    }

    private func resolvedArtwork(for group: MonthlyRecap.RankedGroup, systemImage: String) -> MPMediaItemArtwork? {
        if let artwork = group.artwork {
            return artwork
        }

        if systemImage == "person.fill" {
            return artistArtwork(name: group.title)
        }

        return albumArtwork(title: group.title, artist: group.subtitle)
    }

    private func resolvedTopSong(for song: MonthlyRecap.RankedSong) -> TopSong? {
        manager.song(withPersistentID: song.id)
            ?? manager.song(matchingTitle: song.title, artist: song.artist)
    }

    private func resolvedTopSong(for song: MonthlyRecap.MovementSong) -> TopSong? {
        manager.song(withPersistentID: song.id)
            ?? manager.song(matchingTitle: song.title, artist: song.artist)
    }

    private func resolvedTopAlbum(for group: MonthlyRecap.RankedGroup) -> TopAlbum? {
        if let id = UInt64(group.id),
           let album = manager.album(withPersistentID: id) {
            return album
        }

        return manager.album(matchingTitle: group.title, artist: group.subtitle)
    }

    private func resolvedTopArtist(for group: MonthlyRecap.RankedGroup) -> TopArtist? {
        if let id = UInt64(group.id),
           let artist = manager.artist(withPersistentID: id) {
            return artist
        }

        return manager.artist(matchingName: group.title)
    }

    private func albumArtwork(title: String, artist: String) -> MPMediaItemArtwork? {
        manager.artworkForAlbum(title: title, artist: artist)
    }

    private func artistArtwork(name: String) -> MPMediaItemArtwork? {
        manager.artworkForArtist(name: name)
    }

    private func appendUniqueArtwork(
        key: String,
        artwork: MPMediaItemArtwork?,
        seen: inout Set<String>,
        result: inout [MPMediaItemArtwork]
    ) {
        guard result.count < 6,
              let artwork,
              !key.isEmpty else {
            return
        }

        guard !seen.contains(key) else {
            return
        }

        seen.insert(key)
        result.append(artwork)
    }

    var body: some View {
        ScrollView {
            if !manager.hasLoadedInitialSnapshot && recap.snapshotCount == 0 {
                VStack {
                    ProgressView()
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    RecapHeroPoster(
                        monthTitle: monthTitle,
                        recap: recap,
                        artworks: cachedArtworkHighlights,
                        leadingSong: recap.topSongs.first,
                        leadingSongArtwork: recap.topSongs.first.flatMap(resolvedArtwork(for:)),
                        selectedYear: selectedRecapYear,
                        months: selectedYearMonths,
                        isYearSelected: isShowingYearAggregate,
                        selectedMonthStart: selectedMonthStartOrCurrent,
                        canSelectPrevious: canSelectPreviousMonth,
                        canSelectNext: canSelectNextMonth,
                        onSelectPrevious: selectPreviousMonth,
                        onSelectNext: selectNextMonth,
                        onSelectYear: selectYearAggregate,
                        onSelectMonth: { selectMonth($0) }
                    )

                    if recap.hasActivity {
                        recapSections
                    } else {
                        baselineSection
                    }

                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, isRegularWidth ? 132 : 154)
                .frame(maxWidth: 1120, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
                .offset(x: monthDragDisplayOffset)
                .disabled(isSuppressingRecapNavigation)
                .id(selectedMonthStartOrCurrent)
                .transition(monthContentTransition)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(monthDragAxis == .horizontal)
        .safeAreaInset(edge: .bottom) {
            if isRegularWidth {
                Color.clear
                    .frame(height: 84)
                    .allowsHitTesting(false)
            }
        }
        .refreshable {
            manager.syncRecapFromCloud()
            manager.refreshForRecapSequence(reason: .manualRefresh)
        }
        .background(RecapBackground(palette: recapBackgroundPalette))
        .overlay(alignment: .topTrailing) {
            floatingYearPicker
                .padding(.top, 8)
                .padding(.trailing, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.smooth(duration: 0.26), value: selectedMonthStartOrCurrent)
        .simultaneousGesture(monthSwipeGesture)
        .task(id: artworkHighlightsSignature) {
            updateCachedArtworkHighlightsIfNeeded()
        }
        .onAppear {
            applyPendingRecapMonth()
            syncSelectedMonthIfNeeded()
            scheduleInitialCloudSyncIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMonthlyRecap)) { _ in
            applyPendingRecapMonth()
        }
        .onChange(of: manager.availableRecapMonths) { _, _ in
            syncSelectedMonthIfNeeded()
        }
        .onChange(of: manager.monthlyRecap.monthStart) { _, _ in
            syncSelectedMonthIfNeeded()
        }
        .navigationDestination(item: $selectedRecapDestination) { destination in
            recapDestinationView(for: destination)
        }
    }

    private func applyPendingRecapMonth() {
        guard let month = PlayCountNavigationRequestStore.consumeRequestedRecapMonth() else { return }
        isShowingYearAggregate = false
        selectedMonthStart = normalizedMonth(month)
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    private var recapSections: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: Self.rankingColumns, alignment: .leading, spacing: 18) {
                rankingSections
            }

            if isShowingYearAggregate, hasYearlyMonthlyHighlights {
                yearlyMonthlyBreakdownSection
            }
        }
    }

    @ViewBuilder
    private var rankingSections: some View {
        if isShowingYearAggregate {
            if !recap.topSongs.isEmpty {
                topSongsSection
            }
            if !recap.topAlbums.isEmpty {
                topAlbumsSection
            }
            if !recap.topArtists.isEmpty {
                topArtistsSection
            }
        } else {
            if !recap.biggestGainers.isEmpty {
                biggestGainersSection
            }
            if !recap.topNewSongs.isEmpty {
                topNewSongsSection
            }
            if !recap.topSongs.isEmpty {
                topSongsSection
            }
            if !recap.topAlbums.isEmpty {
                topAlbumsSection
            }
            if !recap.topArtists.isEmpty {
                topArtistsSection
            }
        }
    }

    private static let rankingColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 320, maximum: 540), spacing: 18, alignment: .top)
    ]

    @ViewBuilder
    private var floatingYearPicker: some View {
        if hasMultipleRecapYears {
            Menu {
                ForEach(availableRecapYears, id: \.self) { year in
                    Button {
                        selectYear(year)
                    } label: {
                        if year == selectedRecapYear {
                            Label(String(year), systemImage: "checkmark")
                                .foregroundStyle(.primary)
                        } else {
                            Text(String(year))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(String(selectedRecapYear))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
            }
            .tint(.primary)
            .buttonStyle(.plain)
            .accessibilityLabel("Recap year")
        }
    }

    private var baselineSection: some View {
        RecapSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your baseline is set")
                    .font(.title3.weight(.semibold))
                Text("Come back after listening and your most-played songs, albums, and artists will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var topSongsSection: some View {
        RecapRankingSection(
            title: "Top Songs",
            totalCount: recap.topSongs.count,
            visibleCount: 5
        ) {
            RecapFullSongsView(title: "Top Songs", songs: recap.topSongs, manager: manager, recapContext: recapDrilldownContext)
        } content: {
            ForEach(Array(recap.topSongs.prefix(5).enumerated()), id: \.element.id) { index, song in
                if let topSong = resolvedTopSong(for: song) {
                    Button {
                        openRecapDestination(.song(id: topSong.id, title: topSong.title, artist: topSong.artist))
                    } label: {
                        RecapSongRow(song: song, artwork: resolvedArtwork(for: song))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    RecapSongRow(song: song, artwork: resolvedArtwork(for: song))
                }
            }
        }
    }

    private var biggestGainersSection: some View {
        RecapRankingSection(title: "Biggest Gainers") {
            ForEach(recap.biggestGainers.prefix(5)) { song in
                if let topSong = resolvedTopSong(for: song) {
                    Button {
                        openRecapDestination(.song(id: topSong.id, title: topSong.title, artist: topSong.artist))
                    } label: {
                        RecapMovementRow(song: song, artwork: resolvedArtwork(for: song))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    RecapMovementRow(song: song, artwork: resolvedArtwork(for: song))
                }
            }
        }
    }

    private var topNewSongsSection: some View {
        RecapRankingSection(title: "Top New Songs") {
            ForEach(Array(recap.topNewSongs.prefix(5).enumerated()), id: \.element.id) { index, song in
                if let topSong = resolvedTopSong(for: song) {
                    Button {
                        openRecapDestination(.song(id: topSong.id, title: topSong.title, artist: topSong.artist))
                    } label: {
                        RecapSongRow(song: song, artwork: resolvedArtwork(for: song))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    RecapSongRow(song: song, artwork: resolvedArtwork(for: song))
                }
            }
        }
    }

    private var topAlbumsSection: some View {
        RecapRankingSection(
            title: "Top Albums",
            totalCount: recap.topAlbums.count,
            visibleCount: 5
        ) {
            RecapFullGroupsView(title: "Top Albums", groups: recap.topAlbums, systemImage: "rectangle.stack.fill", manager: manager, recapContext: recapDrilldownContext)
        } content: {
            ForEach(Array(recap.topAlbums.prefix(5).enumerated()), id: \.element.id) { index, album in
                if let topAlbum = resolvedTopAlbum(for: album) {
                    Button {
                        openRecapDestination(.album(id: topAlbum.id, title: topAlbum.title, artist: topAlbum.artist))
                    } label: {
                        RecapGroupRow(group: album, systemImage: "rectangle.stack.fill", artwork: resolvedArtwork(for: album, systemImage: "rectangle.stack.fill"))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    RecapGroupRow(group: album, systemImage: "rectangle.stack.fill", artwork: resolvedArtwork(for: album, systemImage: "rectangle.stack.fill"))
                }
            }
        }
    }

    private var topArtistsSection: some View {
        RecapRankingSection(
            title: "Top Artists",
            totalCount: recap.topArtists.count,
            visibleCount: 5
        ) {
            RecapFullGroupsView(title: "Top Artists", groups: recap.topArtists, systemImage: "person.fill", manager: manager, recapContext: recapDrilldownContext)
        } content: {
            ForEach(Array(recap.topArtists.prefix(5).enumerated()), id: \.element.id) { index, artist in
                if let topArtist = resolvedTopArtist(for: artist) {
                    Button {
                        openRecapDestination(.artist(id: topArtist.id, name: topArtist.name))
                    } label: {
                        RecapGroupRow(group: artist, systemImage: "person.fill", artwork: resolvedArtwork(for: artist, systemImage: "person.fill"))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                } else {
                    RecapGroupRow(group: artist, systemImage: "person.fill", artwork: resolvedArtwork(for: artist, systemImage: "person.fill"))
                }
            }
        }
    }

    private var yearlyMonthlyHighlights: [YearlyMonthlyHighlight] {
        manager.yearlyMonthlyHighlights(for: selectedRecapYear)
            .map { YearlyMonthlyHighlight(month: $0.month, recap: $0.recap) }
    }

    private var hasYearlyMonthlyHighlights: Bool {
        yearlyMonthlyHighlights.contains {
            !$0.recap.topSongs.isEmpty || !$0.recap.topAlbums.isEmpty || !$0.recap.topArtists.isEmpty
        }
    }

    private var yearlyMonthlyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RecapMonthlyBreakdownStrip(
                title: "Top Songs by Month",
                items: yearlyMonthlyHighlights.compactMap { highlight in
                    guard let song = highlight.recap.topSongs.first else { return nil }
                    return RecapMonthlyBreakdownItem(
                        id: "song-\(highlight.id.timeIntervalSinceReferenceDate)",
                        month: highlight.month,
                        title: song.title,
                        subtitle: song.artist,
                        artwork: resolvedArtwork(for: song),
                        kind: .song(song)
                    )
                },
                destination: breakdownDestination(for:),
                onScrollActivityChanged: setYearlyBreakdownScrollActivity
            )

            RecapMonthlyBreakdownStrip(
                title: "Top Albums by Month",
                items: yearlyMonthlyHighlights.compactMap { highlight in
                    guard let album = highlight.recap.topAlbums.first else { return nil }
                    return RecapMonthlyBreakdownItem(
                        id: "album-\(highlight.id.timeIntervalSinceReferenceDate)",
                        month: highlight.month,
                        title: album.title,
                        subtitle: album.subtitle,
                        artwork: resolvedArtwork(for: album, systemImage: "rectangle.stack.fill"),
                        kind: .album(album)
                    )
                },
                destination: breakdownDestination(for:),
                onScrollActivityChanged: setYearlyBreakdownScrollActivity
            )

            RecapMonthlyBreakdownStrip(
                title: "Top Artists by Month",
                items: yearlyMonthlyHighlights.compactMap { highlight in
                    guard let artist = highlight.recap.topArtists.first else { return nil }
                    return RecapMonthlyBreakdownItem(
                        id: "artist-\(highlight.id.timeIntervalSinceReferenceDate)",
                        month: highlight.month,
                        title: artist.title,
                        subtitle: "Top artist",
                        artwork: resolvedArtwork(for: artist, systemImage: "person.fill"),
                        kind: .artist(artist)
                    )
                },
                destination: breakdownDestination(for:),
                onScrollActivityChanged: setYearlyBreakdownScrollActivity
            )
        }
    }

    @ViewBuilder
    private func breakdownDestination(for item: RecapMonthlyBreakdownItem) -> some View {
        switch item.kind {
        case .song(let song):
            if let topSong = resolvedTopSong(for: song) {
                SongInfoView(song: topSong, manager: manager, recapContext: recapDrilldownContext)
            } else {
                RecapUnavailableDetail(title: item.title)
            }
        case .album(let album):
            if let topAlbum = resolvedTopAlbum(for: album) {
                AlbumInfoView(album: topAlbum, manager: manager, recapContext: recapDrilldownContext)
            } else {
                RecapUnavailableDetail(title: item.title)
            }
        case .artist(let artist):
            if let topArtist = resolvedTopArtist(for: artist) {
                ArtistInfoView(artist: topArtist, manager: manager, recapContext: recapDrilldownContext)
            } else {
                RecapUnavailableDetail(title: item.title)
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        RecapSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Debug")
                    .font(.headline)

            Button {
                manager.refreshForRecapSequence(reason: .manualRefresh)
            } label: {
                Label("Refresh Recap", systemImage: "arrow.clockwise")
            }
            .disabled(manager.isLoading)

            Button {
                Task {
                    let granted = await RecapNotificationScheduler.shared.requestAuthorizationAndSchedule()
                    await MainActor.run {
                        reminderStatusMessage = granted ? "Recap reminders scheduled." : "Notifications are not enabled."
                    }
                }
            } label: {
                Label("Enable Reminders", systemImage: "bell.badge")
            }

            Button {
                RecapNotificationScheduler.shared.scheduleDebugRecapNotification()
                reminderStatusMessage = "Test reminder scheduled."
            } label: {
                Label("Send Test Reminder", systemImage: "bell.and.waves.left.and.right")
            }

            Button {
                print(manager.recapDebugSummary())
                reminderStatusMessage = "Snapshot summary printed to console."
            } label: {
                Label("Print Snapshot Summary", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                let result = manager.runRecapSelfCheck()
                print(result)
                reminderStatusMessage = result
            } label: {
                Label("Run Recap Self Check", systemImage: "checkmark.seal")
            }

            if let reminderStatusMessage {
                Text(reminderStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    #endif

    private var monthTitle: String {
        if isShowingYearAggregate {
            return String(selectedRecapYear)
        }
        return Self.monthFormatter.string(from: recap.monthStart)
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard !isUsingYearlyBreakdownStrip else {
                    resetMonthDragState()
                    return
                }

                if monthDragAxis == .undecided {
                    monthDragAxis = resolvedMonthDragAxis(horizontal: horizontal, vertical: vertical)
                }

                guard monthDragAxis == .horizontal else {
                    monthDragOffset = 0
                    return
                }

                suppressRecapNavigationDuringSwipe()
                monthDragOffset = clampedMonthDragOffset(horizontal)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let dragAxis: MonthDragAxis
                if monthDragAxis == .undecided {
                    dragAxis = resolvedMonthDragAxis(horizontal: horizontal, vertical: vertical)
                } else {
                    dragAxis = monthDragAxis
                }
                defer {
                    withAnimation(.smooth(duration: 0.22)) {
                        resetMonthDragState()
                    }
                    releaseRecapNavigationAfterSwipe()
                }

                guard !isUsingYearlyBreakdownStrip else { return }
                guard dragAxis == .horizontal else { return }

                guard abs(horizontal) > 48,
                      abs(horizontal) > abs(vertical) * 1.25 else {
                    return
                }

                if horizontal < 0 {
                    selectNextMonth()
                } else {
                    selectPreviousMonth()
                }
            }
    }

    private var monthDragDisplayOffset: CGFloat {
        clampedMonthDragOffset(monthDragOffset)
    }

    private var monthContentTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: monthTransitionEdge).combined(with: .opacity),
            removal: .opacity
        )
    }

    private func clampedMonthDragOffset(_ offset: CGFloat) -> CGFloat {
        let hasDestination = offset > 0 ? canSelectPreviousMonth : canSelectNextMonth
        let resistance = hasDestination ? 1 : 0.22
        return min(118, max(-118, offset * resistance))
    }

    private func resolvedMonthDragAxis(horizontal: CGFloat, vertical: CGFloat) -> MonthDragAxis {
        let absoluteHorizontal = abs(horizontal)
        let absoluteVertical = abs(vertical)
        guard max(absoluteHorizontal, absoluteVertical) >= 5 else {
            return .undecided
        }

        if absoluteHorizontal > absoluteVertical * 1.2 {
            return .horizontal
        }

        if absoluteVertical >= absoluteHorizontal * 1.1 {
            return .vertical
        }

        return .undecided
    }

    private func resetMonthDragState() {
        monthDragOffset = 0
        monthDragAxis = .undecided
    }

    private func suppressRecapNavigationDuringSwipe() {
        recapNavigationSuppressionToken += 1
        if !isSuppressingRecapNavigation {
            isSuppressingRecapNavigation = true
        }
    }

    private func releaseRecapNavigationAfterSwipe() {
        guard isSuppressingRecapNavigation else { return }
        recapNavigationSuppressionToken += 1
        let token = recapNavigationSuppressionToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard token == recapNavigationSuppressionToken else { return }
            isSuppressingRecapNavigation = false
        }
    }

    private func openRecapDestination(_ destination: RecapNavigationDestination) {
        guard !isSuppressingRecapNavigation, monthDragAxis != .horizontal else { return }
        selectedRecapDestination = destination
    }

    @ViewBuilder
    private func recapDestinationView(for destination: RecapNavigationDestination) -> some View {
        switch destination {
        case .song(let id, let title, let artist):
            if let song = manager.song(withPersistentID: id) ?? manager.song(matchingTitle: title, artist: artist) {
                SongInfoView(song: song, manager: manager, recapContext: recapDrilldownContext)
            } else {
                RecapUnavailableDetail(title: title)
            }
        case .album(let id, let title, let artist):
            if let album = manager.album(withPersistentID: id) ?? manager.album(matchingTitle: title, artist: artist) {
                AlbumInfoView(album: album, manager: manager, recapContext: recapDrilldownContext)
            } else {
                RecapUnavailableDetail(title: title)
            }
        case .artist(let id, let name):
            if let artist = manager.artist(withPersistentID: id) ?? manager.artist(matchingName: name) {
                ArtistInfoView(artist: artist, manager: manager, recapContext: recapDrilldownContext)
            } else {
                RecapUnavailableDetail(title: name)
            }
        }
    }

    private func setYearlyBreakdownScrollActivity(_ isActive: Bool) {
        if isActive {
            isUsingYearlyBreakdownStrip = true
            resetMonthDragState()
            suppressRecapNavigationDuringSwipe()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isUsingYearlyBreakdownStrip = false
                releaseRecapNavigationAfterSwipe()
            }
        }
    }

    private func syncSelectedMonthIfNeeded() {
        let currentSelection = selectedMonthStart.map(normalizedMonth)
        if let currentSelection,
           availableMonthStarts.contains(where: { Calendar.current.isDate($0, equalTo: currentSelection, toGranularity: .month) }) {
            selectedMonthStart = currentSelection
            return
        }

        selectedMonthStart = normalizedMonth(manager.monthlyRecap.monthStart)
    }

    private func selectPreviousMonth() {
        if isShowingYearAggregate {
            selectAdjacentYear(offset: -1)
            return
        }
        guard let selectedMonthIndex else { return }

        if selectedMonthIndex > 0 {
            selectMonth(availableMonthStarts[selectedMonthIndex - 1], transitionEdge: .leading)
            return
        }

        selectYearAggregate(selectedRecapYear, anchorMonth: selectedMonthStartOrCurrent, transitionEdge: .leading)
    }

    private func selectNextMonth() {
        if isShowingYearAggregate {
            guard let firstMonth = selectedYearMonths.first else { return }
            selectMonth(firstMonth, transitionEdge: .trailing)
            return
        }
        guard let selectedMonthIndex, selectedMonthIndex < availableMonthStarts.count - 1 else { return }
        selectMonth(availableMonthStarts[selectedMonthIndex + 1], transitionEdge: .trailing)
    }

    private func selectMonth(_ month: Date, transitionEdge explicitEdge: Edge? = nil) {
        let nextMonth = normalizedMonth(month)
        let currentMonth = selectedMonthStartOrCurrent
        if let explicitEdge {
            monthTransitionEdge = explicitEdge
        } else {
            monthTransitionEdge = nextMonth < currentMonth ? .leading : .trailing
        }

        withAnimation(.smooth(duration: 0.26)) {
            isShowingYearAggregate = false
            selectedMonthStart = nextMonth
        }
    }

    private func selectYear(_ year: Int) {
        let calendar = Calendar.current
        let selectedMonth = calendar.component(.month, from: selectedMonthStartOrCurrent)
        let monthsInYear = availableMonthStarts.filter {
            calendar.component(.year, from: $0) == year
        }

        guard let fallback = monthsInYear.last else { return }
        let matchingMonth = monthsInYear.first {
            calendar.component(.month, from: $0) == selectedMonth
        }

        selectYearAggregate(year, anchorMonth: matchingMonth ?? fallback)
    }

    private func selectYearAggregate() {
        selectYearAggregate(selectedRecapYear, anchorMonth: selectedMonthStartOrCurrent, transitionEdge: nil)
    }

    private func selectAdjacentYear(offset: Int) {
        guard let selectedYearIndex = availableRecapYears.firstIndex(of: selectedRecapYear) else { return }
        let nextIndex = selectedYearIndex + offset
        guard availableRecapYears.indices.contains(nextIndex) else { return }
        selectYear(availableRecapYears[nextIndex])
    }

    private func selectYearAggregate(_ year: Int, anchorMonth: Date, transitionEdge explicitEdge: Edge? = nil) {
        let nextMonth = normalizedMonth(anchorMonth)
        monthTransitionEdge = explicitEdge ?? (nextMonth < selectedMonthStartOrCurrent ? .leading : .trailing)

        withAnimation(.smooth(duration: 0.26)) {
            selectedMonthStart = nextMonth
            isShowingYearAggregate = true
        }
    }

    private func normalizedMonth(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()

    private static let yearlyBreakdownMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL"
        return formatter
    }()

}

private struct RecapHeroPoster: View {
    let monthTitle: String
    let recap: MonthlyRecap
    let artworks: [MPMediaItemArtwork]
    let leadingSong: MonthlyRecap.RankedSong?
    let leadingSongArtwork: MPMediaItemArtwork?
    let selectedYear: Int
    let months: [Date]
    let isYearSelected: Bool
    let selectedMonthStart: Date
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void
    let onSelectYear: () -> Void
    let onSelectMonth: (Date) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isRegularWidth ? 14 : 16) {
            RecapArtworkCollage(artworks: artworks, layout: isRegularWidth ? .regular : .compact)

            titleBlock
            RecapSummaryBar(recap: recap)

            if let leadingSong {
                RecapHeroSpotlight(song: leadingSong, artwork: leadingSongArtwork)
            }
        }
        .padding(.top, 4)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(monthTitle)
                .font(.system(size: isRegularWidth ? 36 : 40, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            RecapPeriodStrip(
                selectedYear: selectedYear,
                months: months,
                isYearSelected: isYearSelected,
                selectedMonthStart: selectedMonthStart,
                canSelectPrevious: canSelectPrevious,
                canSelectNext: canSelectNext,
                onSelectPrevious: onSelectPrevious,
                onSelectNext: onSelectNext,
                onSelectYear: onSelectYear,
                onSelectMonth: onSelectMonth
            )
        }
    }
}

private struct RecapArtworkCollage: View {
    enum Layout {
        case compact
        case regular
    }

    let artworks: [MPMediaItemArtwork]
    let layout: Layout

    var body: some View {
        if artworks.isEmpty {
            emptyArtwork
        } else {
            ZStack {
                ForEach(Array(sideArtworks.enumerated()), id: \.offset) { index, artwork in
                    ArtworkView(
                        artwork: artwork,
                        size: sideArtworkSize(for: index),
                        cornerRadius: sideArtworkCornerRadius(for: index)
                    )
                    .rotationEffect(.degrees(sideArtworkRotation(for: index)))
                    .offset(sideArtworkOffset(for: index))
                    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 8)
                    .zIndex(Double(index))
                }

                if let mainArtwork = artworks.first {
                    ArtworkView(
                        artwork: mainArtwork,
                        size: mainArtworkSize,
                        cornerRadius: layout == .regular ? 28 : 24
                    )
                    .rotationEffect(.degrees(-1.5))
                    .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 16)
                    .zIndex(20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: layout == .regular ? 282 : 228)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recap album artwork collage")
        }
    }

    private var sideArtworks: [MPMediaItemArtwork] {
        Array(artworks.dropFirst().prefix(sideArtworkLimit))
    }

    private var sideArtworkLimit: Int {
        switch layout {
        case .compact:
            return 4
        case .regular:
            return 5
        }
    }

    private var mainArtworkSize: CGSize {
        switch layout {
        case .compact:
            return CGSize(width: 172, height: 172)
        case .regular:
            return CGSize(width: 196, height: 196)
        }
    }

    private func sideArtworkSize(for index: Int) -> CGSize {
        switch layout {
        case .compact:
            switch index {
            case 0, 1:
                return CGSize(width: 108, height: 108)
            case 2, 3:
                return CGSize(width: 82, height: 82)
            default:
                return CGSize(width: 68, height: 68)
            }
        case .regular:
            switch index {
            case 0, 1:
                return CGSize(width: 132, height: 132)
            case 2, 3:
                return CGSize(width: 112, height: 112)
            default:
                return CGSize(width: 96, height: 96)
            }
        }
    }

    private func sideArtworkCornerRadius(for index: Int) -> CGFloat {
        index < 2 ? 18 : 16
    }

    private func sideArtworkRotation(for index: Int) -> Double {
        switch index {
        case 0: return -12
        case 1: return 11
        case 2: return 7
        case 3: return -8
        default: return 4
        }
    }

    private func sideArtworkOffset(for index: Int) -> CGSize {
        switch layout {
        case .compact:
            switch index {
            case 0:
                return CGSize(width: -100, height: 34)
            case 1:
                return CGSize(width: 100, height: 38)
            case 2:
                return CGSize(width: -142, height: 4)
            case 3:
                return CGSize(width: 142, height: 8)
            default:
                return CGSize(width: 0, height: 82)
            }
        case .regular:
            switch index {
            case 0:
                return CGSize(width: -146, height: 52)
            case 1:
                return CGSize(width: 146, height: 58)
            case 2:
                return CGSize(width: -258, height: 8)
            case 3:
                return CGSize(width: 258, height: 14)
            default:
                return CGSize(width: 0, height: 120)
            }
        }
    }

    private var emptyArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
                .frame(width: 172, height: 172)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 242)
    }
}

private struct RecapPeriodStrip: View {
    let selectedYear: Int
    let months: [Date]
    let isYearSelected: Bool
    let selectedMonthStart: Date
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void
    let onSelectYear: () -> Void
    let onSelectMonth: (Date) -> Void

    var body: some View {
        HStack(spacing: 8) {
            navigationButton(systemImage: "chevron.left", label: "Previous recap", isEnabled: canSelectPrevious, action: onSelectPrevious)

            Menu {
                Button(action: onSelectYear) {
                    periodMenuLabel(title: String(selectedYear), isSelected: isYearSelected)
                }

                Divider()

                ForEach(months, id: \.timeIntervalSinceReferenceDate) { month in
                    let isSelected = !isYearSelected && Calendar.current.isDate(month, equalTo: selectedMonthStart, toGranularity: .month)
                    Button {
                        onSelectMonth(month)
                    } label: {
                        periodMenuLabel(title: Self.fullMonthFormatter.string(from: month), isSelected: isSelected)
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Text(selectedPeriodTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.primary.opacity(0.055), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                }
            }
            .buttonStyle(.plain)

            navigationButton(systemImage: "chevron.right", label: "Next recap", isEnabled: canSelectNext, action: onSelectNext)
        }
        .accessibilityLabel("Recap period")
    }

    private var selectedPeriodTitle: String {
        isYearSelected ? String(selectedYear) : Self.fullMonthFormatter.string(from: selectedMonthStart)
    }

    private func navigationButton(systemImage: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.055), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private func periodMenuLabel(title: String, isSelected: Bool) -> some View {
        Label(title, systemImage: isSelected ? "checkmark" : "calendar")
    }

    private static let fullMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}

private struct RecapHeroSpotlight: View {
    let song: MonthlyRecap.RankedSong
    let artwork: MPMediaItemArtwork?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                artwork: artwork ?? song.artwork,
                size: CGSize(width: 64, height: 64),
                cornerRadius: 13
            )

            VStack(alignment: .leading, spacing: 3) {
                Text("Most Played")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            MetricBadge(text: "+\(song.playDelta)")
        }
        .padding(10)
        .playCountCardSurface(cornerRadius: 16)
    }
}

private struct RecapSummaryBar: View {
    let recap: MonthlyRecap

    var body: some View {
        HStack(spacing: 0) {
            RecapSummaryItem(title: "Plays", value: "\(recap.totalPlayDelta)", systemImage: "play.fill")
            Divider()
                .padding(.vertical, 8)
            RecapSummaryItem(title: "Time", value: recap.totalListeningDuration.formattedListeningMinutes, systemImage: "clock.fill")
            Divider()
                .padding(.vertical, 8)
            RecapSummaryItem(title: "Songs", value: "\(recap.playedSongCount)", systemImage: "music.note")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .playCountCardSurface(cornerRadius: 16)
    }
}

private struct RecapSummaryItem: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RecapRankingSection<Content: View, Destination: View>: View {
    let title: String
    let totalCount: Int
    let visibleCount: Int
    let destination: (() -> Destination)?
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) where Destination == EmptyView {
        self.title = title
        totalCount = 0
        visibleCount = 0
        destination = nil
        self.content = content()
    }

    init(
        title: String,
        totalCount: Int,
        visibleCount: Int,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.totalCount = totalCount
        self.visibleCount = visibleCount
        self.destination = destination
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                Spacer()
                if totalCount > visibleCount, let destination {
                    NavigationLink {
                        destination()
                    } label: {
                        Text("See All")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }

            RecapSurface {
                VStack(spacing: 0) {
                    content
                }
            }
        }
    }
}

private struct RecapFullSongsView: View {
    let title: String
    let songs: [MonthlyRecap.RankedSong]
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext

    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                if let topSong = resolvedTopSong(for: song) {
                    NavigationLink {
                        SongInfoView(song: topSong, manager: manager, recapContext: recapContext)
                    } label: {
                        RecapSongRow(rank: index + 1, song: song, rankStyle: .prominentTopThree)
                    }
                } else {
                    RecapSongRow(rank: index + 1, song: song, rankStyle: .prominentTopThree)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .toolbar(.visible, for: .navigationBar)
    }

    private func resolvedTopSong(for song: MonthlyRecap.RankedSong) -> TopSong? {
        manager.song(withPersistentID: song.id)
            ?? manager.song(matchingTitle: song.title, artist: song.artist)
    }
}

private struct RecapFullGroupsView: View {
    let title: String
    let groups: [MonthlyRecap.RankedGroup]
    let systemImage: String
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext

    var body: some View {
        List {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if systemImage == "person.fill",
                   let artist = resolvedTopArtist(for: group) {
                    NavigationLink {
                        ArtistInfoView(artist: artist, manager: manager, recapContext: recapContext)
                    } label: {
                        RecapGroupRow(rank: index + 1, group: group, systemImage: systemImage, rankStyle: .prominentTopThree)
                    }
                } else if let album = resolvedTopAlbum(for: group) {
                    NavigationLink {
                        AlbumInfoView(album: album, manager: manager, recapContext: recapContext)
                    } label: {
                        RecapGroupRow(rank: index + 1, group: group, systemImage: systemImage, rankStyle: .prominentTopThree)
                    }
                } else {
                    RecapGroupRow(rank: index + 1, group: group, systemImage: systemImage, rankStyle: .prominentTopThree)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .toolbar(.visible, for: .navigationBar)
    }

    private func resolvedTopAlbum(for group: MonthlyRecap.RankedGroup) -> TopAlbum? {
        if let id = UInt64(group.id),
           let album = manager.album(withPersistentID: id) {
            return album
        }

        return manager.album(matchingTitle: group.title, artist: group.subtitle)
    }

    private func resolvedTopArtist(for group: MonthlyRecap.RankedGroup) -> TopArtist? {
        if let id = UInt64(group.id),
           let artist = manager.artist(withPersistentID: id) {
            return artist
        }

        return manager.artist(matchingName: group.title)
    }
}

private struct RecapFullMovementView: View {
    let title: String
    let songs: [MonthlyRecap.MovementSong]
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext

    var body: some View {
        List {
            ForEach(songs) { song in
                if let topSong = resolvedTopSong(for: song) {
                    NavigationLink {
                        SongInfoView(song: topSong, manager: manager, recapContext: recapContext)
                    } label: {
                        RecapMovementRow(song: song)
                    }
                } else {
                    RecapMovementRow(song: song)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle(title)
        .toolbar(.visible, for: .navigationBar)
    }

    private func resolvedTopSong(for song: MonthlyRecap.MovementSong) -> TopSong? {
        manager.song(withPersistentID: song.id)
            ?? manager.song(matchingTitle: song.title, artist: song.artist)
    }
}

private struct RecapMovementRow: View {
    let song: MonthlyRecap.MovementSong
    let artwork: MPMediaItemArtwork?

    init(song: MonthlyRecap.MovementSong, artwork: MPMediaItemArtwork? = nil) {
        self.song = song
        self.artwork = artwork
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                artwork: artwork ?? song.artwork,
                size: CGSize(width: 58, height: 58),
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(rankSubtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Label("\(song.rankChange)", systemImage: "arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Up \(song.rankChange) ranks")
                Text("+\(song.playDelta) plays")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 9)
    }

    private var rankSubtitle: String {
        if let previousRank = song.previousRank {
            return "#\(previousRank) to #\(song.currentRank)"
        }
        return "New at #\(song.currentRank)"
    }
}

private struct RecapStatTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 86)
        .padding(10)
        .playCountCardSurface(cornerRadius: 16)
    }
}

private enum RecapMonthlyBreakdownKind {
    case song(MonthlyRecap.RankedSong)
    case album(MonthlyRecap.RankedGroup)
    case artist(MonthlyRecap.RankedGroup)

    var isArtist: Bool {
        if case .artist = self {
            return true
        }
        return false
    }
}

private struct RecapMonthlyBreakdownItem: Identifiable {
    let id: String
    let month: Date
    let title: String
    let subtitle: String
    let artwork: MPMediaItemArtwork?
    let kind: RecapMonthlyBreakdownKind
}

private struct RecapMonthlyBreakdownStrip<Destination: View>: View {
    let title: String
    let items: [RecapMonthlyBreakdownItem]
    let destination: (RecapMonthlyBreakdownItem) -> Destination
    let onScrollActivityChanged: (Bool) -> Void

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))

                RecapSurface {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink {
                                    destination(item)
                                } label: {
                                    RecapMonthlyBreakdownCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(scrollActivityGesture)
                }
            }
        }
    }

    private var scrollActivityGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                onScrollActivityChanged(true)
            }
            .onEnded { _ in
                onScrollActivityChanged(false)
            }
    }
}

private struct RecapMonthlyBreakdownCard: View {
    let item: RecapMonthlyBreakdownItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.kind.isArtist {
                ArtistArtworkView(artwork: item.artwork, name: item.title, diameter: 108)
            } else {
                ArtworkView(
                    artwork: item.artwork,
                    size: CGSize(width: 108, height: 108),
                    cornerRadius: 16
                )
            }

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(width: 108, alignment: .leading)

            Text(Self.monthFormatter.string(from: item.month))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 108, alignment: .leading)
        }
        .frame(width: 108, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityLabel("\(Self.monthFormatter.string(from: item.month)): \(item.title), \(item.subtitle)")
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        return formatter
    }()
}

private struct RecapUnavailableDetail: View {
    let title: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: "music.note",
            description: Text("This item is no longer available in your library.")
        )
        .navigationTitle(title)
    }
}

private struct RecapSongRow: View {
    let rank: Int?
    let song: MonthlyRecap.RankedSong
    let artwork: MPMediaItemArtwork?
    let rankStyle: RankBadgeView.Style

    init(rank: Int? = nil, song: MonthlyRecap.RankedSong, artwork: MPMediaItemArtwork? = nil, rankStyle: RankBadgeView.Style = .plain) {
        self.rank = rank
        self.song = song
        self.artwork = artwork
        self.rankStyle = rankStyle
    }

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                RankBadgeView(rank: rank, style: rankStyle)
            }
            ArtworkView(
                artwork: artwork ?? song.artwork,
                size: CGSize(width: 58, height: 58),
                cornerRadius: 10
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(song.listeningDuration.formattedListeningMinutes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: "+\(song.playDelta)")
        }
        .padding(.vertical, 9)
    }
}

private struct RecapGroupRow: View {
    let rank: Int?
    let group: MonthlyRecap.RankedGroup
    let systemImage: String
    let artwork: MPMediaItemArtwork?
    let rankStyle: RankBadgeView.Style

    init(rank: Int? = nil, group: MonthlyRecap.RankedGroup, systemImage: String, artwork: MPMediaItemArtwork? = nil, rankStyle: RankBadgeView.Style = .plain) {
        self.rank = rank
        self.group = group
        self.systemImage = systemImage
        self.artwork = artwork
        self.rankStyle = rankStyle
    }

    var body: some View {
        HStack(spacing: 12) {
            if let rank {
                RankBadgeView(rank: rank, style: rankStyle)
            }

            if systemImage == "person.fill" {
                ArtistArtworkView(artwork: artwork ?? group.artwork, name: group.title, diameter: 58)
            } else {
                ArtworkView(
                    artwork: artwork ?? group.artwork,
                    size: CGSize(width: 58, height: 58),
                    cornerRadius: 10
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(group.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(group.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(group.listeningDuration.formattedListeningMinutes)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: "+\(group.playDelta)")
        }
        .padding(.vertical, 9)
    }
}

private struct RecapSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .playCountCardSurface(cornerRadius: 20)
    }
}

private struct RecapBackgroundPalette {
    let primary: Color
    let secondary: Color
    let tertiary: Color

    init(artworks: [MPMediaItemArtwork], fallbackSeed: UInt64) {
        let components = artworks
            .prefix(3)
            .compactMap { $0.averageColorComponents() }

        guard let first = components.first else {
            let colors = Self.colors(seed: fallbackSeed)
            self.primary = colors.primary
            self.secondary = colors.secondary
            self.tertiary = colors.tertiary
            return
        }

        let second = components.dropFirst().first ?? first
        let third = components.dropFirst(2).first ?? Self.blend(first, second)

        self.primary = Self.color(from: first, transform: .darken(0.24))
        self.secondary = Self.color(from: second, transform: .boost(0.18))
        self.tertiary = Self.color(from: third, transform: .boost(0.36))
    }

    init(seed: UInt64) {
        let colors = Self.colors(seed: seed)
        primary = colors.primary
        secondary = colors.secondary
        tertiary = colors.tertiary
    }

    private static func colors(seed: UInt64) -> (primary: Color, secondary: Color, tertiary: Color) {
        let hue = Double(seed % 360) / 360.0
        return (
            Color(hue: hue, saturation: 0.58, brightness: 0.94),
            Color(hue: (hue + 0.13).truncatingRemainder(dividingBy: 1), saturation: 0.52, brightness: 0.96),
            Color(hue: (hue + 0.58).truncatingRemainder(dividingBy: 1), saturation: 0.42, brightness: 0.92)
        )
    }

    private enum ComponentTransform {
        case darken(Double)
        case boost(Double)
    }

    private static func color(
        from components: (Double, Double, Double),
        transform: ComponentTransform
    ) -> Color {
        Color(
            red: transformed(components.0, transform: transform),
            green: transformed(components.1, transform: transform),
            blue: transformed(components.2, transform: transform)
        )
    }

    private static func transformed(_ component: Double, transform: ComponentTransform) -> Double {
        switch transform {
        case .darken(let amount):
            return max(component * (1 - amount), 0)
        case .boost(let amount):
            return min(component + (1 - component) * amount, 1)
        }
    }

    private static func blend(
        _ lhs: (Double, Double, Double),
        _ rhs: (Double, Double, Double)
    ) -> (Double, Double, Double) {
        (
            (lhs.0 + rhs.0) / 2,
            (lhs.1 + rhs.1) / 2,
            (lhs.2 + rhs.2) / 2
        )
    }
}

private struct RecapBackground: View {
    let palette: RecapBackgroundPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    palette.primary.opacity(primaryOpacity),
                    palette.secondary.opacity(secondaryOpacity),
                    palette.tertiary.opacity(tertiaryOpacity),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color(.systemBackground)
                .opacity(colorScheme == .dark ? 0.18 : 0.30)
        }
        .ignoresSafeArea()
    }

    private var primaryOpacity: Double {
        colorScheme == .dark ? 0.42 : 0.38
    }

    private var secondaryOpacity: Double {
        colorScheme == .dark ? 0.34 : 0.30
    }

    private var tertiaryOpacity: Double {
        colorScheme == .dark ? 0.30 : 0.22
    }
}

private extension String {
    var normalizedRecapArtworkKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var recapAlbumArtworkKey: String {
        normalizedRecapArtworkKey
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

#if DEBUG
#Preview {
    MonthlyRecapView(manager: .previewPlaying)
}
#endif
