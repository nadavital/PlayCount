import Charts
import MediaPlayer
import SwiftUI

private extension View {
    @ViewBuilder
    func recapFloatingGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
    }

    @ViewBuilder
    func recapMonthDragOffset(_ offset: CGFloat?) -> some View {
        if let offset {
            self.offset(x: offset)
        } else {
            self
        }
    }

    func recapCollageFrame(height: CGFloat, label: String) -> some View {
        self
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }

}

private enum RecapGainerCategory: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"

    var id: Self { self }
}

private enum YearlyRecapSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case trends = "Trends"
    case byMonth = "Months"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2.fill"
        case .trends: "chart.xyaxis.line"
        case .byMonth: "calendar"
        }
    }
}

struct MonthlyRecapView: View {
    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedMonthStart: Date?
    @State private var isShowingYearAggregate = false
    @State private var monthDragOffset: CGFloat = 0
    @State private var monthDragAxis: MonthDragAxis = .undecided
    @State private var isSuppressingRecapNavigation = false
    @State private var recapNavigationSuppressionToken = 0
    @State private var selectedRecapDestination: RecapNavigationDestination?
    @State private var cachedArtworkHighlights: [MPMediaItemArtwork] = []
    @State private var cachedArtworkHighlightsSignature = ""
    @State private var cachedRecapBackgroundPalette: RecapBackgroundPalette?
    @State private var hasScheduledInitialCloudSync = false
    @State private var isPresentingShareStudio = false
    @State private var selectedYearlySection: YearlyRecapSection = .overview

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

    private struct RecapGainersSection: View {
        let songs: [MonthlyRecap.MovementSong]
        let albums: [MonthlyRecap.MovementGroup]
        let artists: [MonthlyRecap.MovementGroup]
        @ObservedObject var manager: MediaLibraryManager
        let recapContext: RecapDrilldownContext
        let openDestination: (RecapNavigationDestination) -> Void
        @State private var selection: RecapGainerCategory = .songs

        private var availableKinds: [RecapGainerCategory] {
            RecapGainerCategory.allCases.filter {
                switch $0 { case .songs: !songs.isEmpty; case .albums: !albums.isEmpty; case .artists: !artists.isEmpty }
            }
        }

        var body: some View {
            RecapRankingSection(
                title: "Biggest Gainers",
                totalCount: selectedCount,
                visibleCount: 5
            ) {
                RecapFullGainersView(
                    category: selection,
                    songs: songs,
                    albums: albums,
                    artists: artists,
                    manager: manager,
                    recapContext: recapContext
                )
            } content: {
                VStack(spacing: 8) {
                    if availableKinds.count > 1 {
                        Picker("Gainer category", selection: $selection) {
                            ForEach(availableKinds) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                    }
                    rows
                }
                .onAppear { normalizeSelection() }
                .onChange(of: availableKinds) { _, _ in normalizeSelection() }
            }
        }

        private var selectedCount: Int {
            switch selection {
            case .songs: songs.count
            case .albums: albums.count
            case .artists: artists.count
            }
        }

        @ViewBuilder private var rows: some View {
            switch selection {
            case .songs:
                ForEach(songs.prefix(5)) { song in
                    Button {
                        if let item = manager.song(withPersistentID: song.id) ?? manager.song(matchingTitle: song.title, artist: song.artist) {
                            openDestination(.song(id: item.id, title: item.title, artist: item.artist))
                        }
                    } label: { RecapMovementRow(song: song).contentShape(.rect) }
                    .buttonStyle(.plain)
                }
            case .albums:
                ForEach(albums.prefix(5)) { group in
                    Button {
                        if let item = resolveAlbum(group) { openDestination(.album(id: item.id, title: item.title, artist: item.artist)) }
                    } label: { RecapGroupMovementRow(group: group, systemImage: "rectangle.stack.fill").contentShape(.rect) }
                    .buttonStyle(.plain)
                }
            case .artists:
                ForEach(artists.prefix(5)) { group in
                    Button {
                        if let item = resolveArtist(group) { openDestination(.artist(id: item.id, name: item.name)) }
                    } label: { RecapGroupMovementRow(group: group, systemImage: "person.fill").contentShape(.rect) }
                    .buttonStyle(.plain)
                }
            }
        }

        private func normalizeSelection() {
            if !availableKinds.contains(selection), let first = availableKinds.first { selection = first }
        }

        private func resolveAlbum(_ group: MonthlyRecap.MovementGroup) -> TopAlbum? {
            if let id = UInt64(group.id), let item = manager.album(withPersistentID: id) { return item }
            return manager.album(matchingTitle: group.title, artist: group.subtitle)
        }

        private func resolveArtist(_ group: MonthlyRecap.MovementGroup) -> TopArtist? {
            if let id = UInt64(group.id), let item = manager.artist(withPersistentID: id) { return item }
            return manager.artist(matchingName: group.title)
        }
    }

    private enum ScrollAnchor {
        static let recapTop = "recap-top"
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

    private var selectedRecapPageIdentifier: String {
        if isShowingYearAggregate {
            return "year-\(selectedRecapYear)"
        }
        return "month-\(selectedMonthStartOrCurrent.timeIntervalSinceReferenceDate)"
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

        for album in recap.topAlbums {
            appendUniqueArtwork(
                key: album.title.recapAlbumArtworkKey,
                artwork: resolvedArtwork(for: album, systemImage: "rectangle.stack.fill"),
                seen: &seen,
                result: &result
            )
        }

        // Artist artwork is usually borrowed from one of the artist's albums.
        // Only use it when the month has no song or album artwork so a sparse
        // recap stays sparse instead of repeating the same release as filler.
        if result.isEmpty, let artist = recap.topArtists.first {
            appendUniqueArtwork(
                key: artist.title.normalizedRecapArtworkKey,
                artwork: resolvedArtwork(for: artist, systemImage: "person.fill"),
                seen: &seen,
                result: &result
            )
        }

        return result
    }

    private var artworkHighlightsSignature: String {
        let recapSongIDs = (recap.topSongs.prefix(6).map(\.id) + recap.topNewSongs.prefix(6).map(\.id))
            .map { String($0) }
            .joined(separator: ",")
        let recapAlbumIDs = recap.topAlbums.prefix(6).map(\.id).joined(separator: ",")
        let recapArtistIDs = recap.topArtists.prefix(6).map(\.id).joined(separator: ",")
        return [
            String(recap.monthStart.timeIntervalSinceReferenceDate),
            String(recap.generatedAt.timeIntervalSinceReferenceDate),
            recapSongIDs,
            recapAlbumIDs,
            recapArtistIDs
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                Color.clear
                    .frame(height: 0)
                    .id(ScrollAnchor.recapTop)

                if (!manager.hasLoadedInitialSnapshot && recap.snapshotCount == 0)
                    || (manager.isPreparingInsights && !recap.hasActivity) {
                    VStack {
                        PlayCountLoadingMark(size: 48)
                        Text("Preparing your recap…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        RecapHeroPoster(
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

                        if isShowingYearAggregate, recap.unattributedPlayDelta > 0 {
                            RecapTrackingCoverageNotice(
                                playCount: recap.unattributedPlayDelta,
                                listeningDuration: recap.unattributedListeningDuration
                            )
                        }

                        if shouldShowWeeklyInsights {
                            RecapWeeklyInsightSection(
                                comparison: manager.weeklyRecapComparison,
                                artwork: weeklyTopSongArtwork
                            )
                        }

                        if !displayedRecapMilestones.isEmpty {
                            RecapMilestonesSection(
                                displayedMilestones: displayedRecapMilestones,
                                allMilestones: recapMilestones,
                                periodLabel: milestonePeriodLabel,
                                showsFullCollection: isShowingYearAggregate,
                                showsUpcomingMilestones: isShowingYearAggregate || isCurrentCalendarMonth
                            )
                        }

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
                    .recapMonthDragOffset(
                        isMonthSwipeEnabled && monthDragAxis == .horizontal ? monthDragDisplayOffset : nil
                    )
                    .disabled(isSuppressingRecapNavigation)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDisabled(isMonthSwipeEnabled && monthDragAxis == .horizontal)
            .onChange(of: selectedRecapPageIdentifier) { _, _ in
                scrollProxy.scrollTo(ScrollAnchor.recapTop, anchor: .top)
            }
        }
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
        .navigationTitle("Recap")
        .playCountPrimaryTitleDisplayMode()
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                recapYearPicker
                recapShareButton
            }
        }
        .simultaneousGesture(monthSwipeGesture, including: monthSwipeGestureMask)
        .task(id: artworkHighlightsSignature) {
            updateCachedArtworkHighlightsIfNeeded()
        }
        .onAppear {
            applyPendingRecapMonth()
            syncSelectedMonthIfNeeded()
            scheduleInitialCloudSyncIfNeeded()
            applyScreenshotPresentationIfNeeded()
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
        .sheet(isPresented: $isPresentingShareStudio) {
            RecapShareStudio(
                recap: recap,
                periodTitle: monthTitle,
                palette: RecapSharePalette(
                    artworks: cachedArtworkHighlights,
                    fallbackSeed: recapBackgroundSeed
                ),
                trendPoints: isShowingYearAggregate ? yearlyTrendPoints : []
            )
        }
    }

    private func applyPendingRecapMonth() {
        guard let month = PlayCountNavigationRequestStore.consumeRequestedRecapMonth() else { return }
        isShowingYearAggregate = false
        selectedMonthStart = normalizedMonth(month)
    }

    private func applyScreenshotPresentationIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-PlayCountScreenshotYearlyRecap") {
            selectYearAggregate()
        }
        if let index = arguments.firstIndex(of: "-PlayCountScreenshotYearlySection"),
           arguments.indices.contains(index + 1) {
            selectedYearlySection = switch arguments[index + 1].lowercased() {
            case "trends": .trends
            case "month", "months", "bymonth": .byMonth
            default: .overview
            }
        }
        if arguments.contains("-PlayCountScreenshotShareStudio") {
            DispatchQueue.main.async {
                isPresentingShareStudio = true
            }
        }
        #endif
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    @ViewBuilder
    private var recapShareButton: some View {
        if recap.hasActivity {
            Button {
                isPresentingShareStudio = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Share recap")
        }
    }

    @ViewBuilder
    private var recapSections: some View {
        VStack(alignment: .leading, spacing: 22) {
            if isShowingYearAggregate {
                RecapYearSectionPicker(selection: $selectedYearlySection)

                switch selectedYearlySection {
                case .overview:
                    LazyVGrid(columns: Self.rankingColumns, alignment: .leading, spacing: 18) {
                        yearlyRankingSections
                    }
                case .trends:
                    if !yearlyTrendPoints.isEmpty {
                        RecapYearTrendSection(points: yearlyTrendPoints)
                    }
                    if !recap.biggestGainers.isEmpty || !recap.biggestAlbumGainers.isEmpty || !recap.biggestArtistGainers.isEmpty {
                        biggestGainersSection
                    }
                case .byMonth:
                    if hasYearlyMonthlyHighlights {
                        yearlyMonthlyBreakdownSection
                    }
                }
            } else {
                LazyVGrid(columns: Self.rankingColumns, alignment: .leading, spacing: 18) {
                    monthlyRankingSections
                }
            }
        }
    }

    @ViewBuilder
    private var yearlyRankingSections: some View {
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

    @ViewBuilder
    private var monthlyRankingSections: some View {
        if !recap.biggestGainers.isEmpty || !recap.biggestAlbumGainers.isEmpty || !recap.biggestArtistGainers.isEmpty {
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

    private static let rankingColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 320, maximum: 540), spacing: 18, alignment: .top)
    ]

    @ViewBuilder
    private var recapYearPicker: some View {
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
            }
            .tint(.primary)
            .accessibilityLabel("Recap year")
        }
    }

    private var baselineSection: some View {
        RecapSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(recap.snapshotCount == 0 ? "No tracking data" : "Your baseline is set")
                    .font(.title3.weight(.semibold))
                Text(
                    recap.snapshotCount == 0
                        ? "PlayCount didn't observe your library during this month, so it won't guess where your plays belong."
                        : "Come back after listening and your most-played songs, albums, and artists will appear here."
                )
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
            ForEach(recap.topSongs.prefix(5).enumerated(), id: \.element.id) { index, song in
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
        RecapGainersSection(
            songs: recap.biggestGainers,
            albums: recap.biggestAlbumGainers,
            artists: recap.biggestArtistGainers,
            manager: manager,
            recapContext: recapDrilldownContext,
            openDestination: openRecapDestination
        )
    }

    private var topNewSongsSection: some View {
        RecapRankingSection(title: "Top New Songs") {
            ForEach(recap.topNewSongs.prefix(5).enumerated(), id: \.element.id) { index, song in
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
            ForEach(recap.topAlbums.prefix(5).enumerated(), id: \.element.id) { index, album in
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
            ForEach(recap.topArtists.prefix(5).enumerated(), id: \.element.id) { index, artist in
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

    private var yearlyTrendPoints: [RecapShareTrendPoint] {
        yearlyMonthlyHighlights.map {
            RecapShareTrendPoint(
                month: $0.month,
                plays: $0.recap.totalPlayDelta,
                listeningMinutes: $0.recap.totalListeningDuration / 60,
                uniqueSongs: $0.recap.playedSongCount,
                uniqueArtists: $0.recap.listenedArtistCount
            )
        }
    }

    private var yearlyMonthlyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !yearlyMilestoneMoments.isEmpty {
                RecapMonthlyMilestoneStrip(
                    moments: yearlyMilestoneMoments,
                    onSelectMonth: selectMonth
                )
            }

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
                destination: breakdownDestination(for:)
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
                destination: breakdownDestination(for:)
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
                destination: breakdownDestination(for:)
            )
        }
    }

    private var yearlyMilestoneMoments: [RecapMonthlyMilestoneMoment] {
        yearlyMonthlyHighlights.compactMap { highlight in
            let current = RecapMilestoneEngine.milestones(
                for: manager.yearToDateRecap(through: highlight.month),
                periodName: "\(selectedRecapYear) through \(highlight.month.formatted(.dateTime.month(.wide)))"
            )
            let previous: [RecapMilestone]
            if let priorMonth = Calendar.current.date(byAdding: .month, value: -1, to: highlight.month),
               Calendar.current.component(.year, from: priorMonth) == selectedRecapYear {
                previous = RecapMilestoneEngine.milestones(
                    for: manager.yearToDateRecap(through: priorMonth),
                    periodName: String(selectedRecapYear)
                )
            } else {
                previous = []
            }
            let unlocked = MilestoneCollectionPresentation.newlyEarned(current: current, previous: previous)
            guard !unlocked.isEmpty else { return nil }
            return RecapMonthlyMilestoneMoment(month: highlight.month, milestones: unlocked)
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

    private var shouldShowWeeklyInsights: Bool {
        guard !isShowingYearAggregate else { return false }
        return Calendar.current.isDate(
            selectedMonthStartOrCurrent,
            equalTo: manager.monthlyRecap.monthStart,
            toGranularity: .month
        )
    }

    private var recapMilestones: [RecapMilestone] {
        RecapMilestoneEngine.milestones(
            for: milestoneRecap,
            periodName: milestonePeriodDescription
        )
    }

    private var displayedRecapMilestones: [RecapMilestone] {
        guard !isShowingYearAggregate else { return recapMilestones }
        return MilestoneCollectionPresentation.monthlyHighlights(
            current: recapMilestones,
            previous: previousMonthMilestones,
            includesNearby: isCurrentCalendarMonth
        )
    }

    private var isCurrentCalendarMonth: Bool {
        Calendar.current.isDate(
            selectedMonthStartOrCurrent,
            equalTo: Date(),
            toGranularity: .month
        )
    }

    private var previousMonthMilestones: [RecapMilestone] {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(
            byAdding: .month,
            value: -1,
            to: selectedMonthStartOrCurrent
        ), calendar.component(.year, from: previousMonth) == selectedRecapYear else {
            return []
        }
        let previousRecap = manager.yearToDateRecap(through: previousMonth)
        return RecapMilestoneEngine.milestones(
            for: previousRecap,
            periodName: String(selectedRecapYear) + " through " + previousMonth.formatted(.dateTime.month(.wide))
        )
    }

    private var milestoneRecap: MonthlyRecap {
        if isShowingYearAggregate {
            return recap
        }
        return manager.yearToDateRecap(through: selectedMonthStartOrCurrent)
    }

    private var milestonePeriodDescription: String {
        if isShowingYearAggregate {
            return String(selectedRecapYear)
        }
        let month = selectedMonthStartOrCurrent.formatted(.dateTime.month(.wide))
        return String(selectedRecapYear) + " through " + month
    }

    private var milestonePeriodLabel: String {
        if isShowingYearAggregate {
            return String(selectedRecapYear)
        }
        let month = selectedMonthStartOrCurrent.formatted(.dateTime.month(.wide))
        return isCurrentCalendarMonth ? "Unlocked or within reach in \(month)" : "Unlocked in \(month)"
    }

    private var weeklyTopSongArtwork: MPMediaItemArtwork? {
        guard let song = manager.weeklyRecapComparison.current.topSong else { return nil }
        return manager.song(withPersistentID: song.id)?.artwork
            ?? manager.song(matchingTitle: song.title, artist: song.artist)?.artwork
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height

                if monthDragAxis == .undecided {
                    guard resolvedMonthDragAxis(horizontal: horizontal, vertical: vertical) == .horizontal else {
                        return
                    }
                    monthDragAxis = .horizontal
                }

                guard monthDragAxis == .horizontal else { return }

                suppressRecapNavigationDuringSwipe()
                monthDragOffset = clampedMonthDragOffset(horizontal)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard monthDragAxis == .horizontal else { return }
                defer {
                    withAnimation(.smooth(duration: 0.22)) { resetMonthDragState() }
                    releaseRecapNavigationAfterSwipe()
                }

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

    private var monthSwipeGestureMask: GestureMask {
        isMonthSwipeEnabled ? .all : .none
    }

    private var isMonthSwipeEnabled: Bool {
        !(isShowingYearAggregate && selectedYearlySection == .byMonth)
    }

    private var monthDragDisplayOffset: CGFloat {
        clampedMonthDragOffset(monthDragOffset)
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
            selectMonth(availableMonthStarts[selectedMonthIndex - 1])
            return
        }

        selectYearAggregate(selectedRecapYear, anchorMonth: selectedMonthStartOrCurrent)
    }

    private func selectNextMonth() {
        if isShowingYearAggregate {
            guard let firstMonth = selectedYearMonths.first else { return }
            selectMonth(firstMonth)
            return
        }
        guard let selectedMonthIndex, selectedMonthIndex < availableMonthStarts.count - 1 else { return }
        selectMonth(availableMonthStarts[selectedMonthIndex + 1])
    }

    private func selectMonth(_ month: Date) {
        isShowingYearAggregate = false
        selectedMonthStart = normalizedMonth(month)
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
        selectYearAggregate(selectedRecapYear, anchorMonth: selectedMonthStartOrCurrent)
    }

    private func selectAdjacentYear(offset: Int) {
        guard let selectedYearIndex = availableRecapYears.firstIndex(of: selectedRecapYear) else { return }
        let nextIndex = selectedYearIndex + offset
        guard availableRecapYears.indices.contains(nextIndex) else { return }
        selectYear(availableRecapYears[nextIndex])
    }

    private func selectYearAggregate(_ year: Int, anchorMonth: Date) {
        let nextMonth = normalizedMonth(anchorMonth)
        selectedMonthStart = nextMonth
        isShowingYearAggregate = true
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

private struct RecapYearSectionPicker: View {
    @Binding var selection: YearlyRecapSection

    var body: some View {
        Picker("Yearly recap section", selection: $selection) {
            ForEach(YearlyRecapSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }
}

private struct RecapYearTrendSection: View {
    private enum Metric: String, CaseIterable, Identifiable {
        case plays = "Plays"
        case listeningTime = "Time"
        case songs = "Songs"
        case artists = "Artists"

        var id: Self { self }
    }

    let points: [RecapShareTrendPoint]
    @State private var selectedMetric: Metric = .plays
    @State private var selectedMonth: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listening Trends")
                .font(.title3.weight(.semibold))

            RecapSurface {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Yearly trend metric", selection: $selectedMetric) {
                        ForEach(Metric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(totalValue)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .contentTransition(.numericText())
                        Spacer()
                        if let focusedPoint {
                            Text(focusedPoint.month.formatted(.dateTime.month(.abbreviated)))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(formattedValue(for: focusedPoint))
                                .font(.subheadline.monospacedDigit())
                        }
                    }

                    Chart(points) { point in
                        BarMark(
                            x: .value("Month", point.month, unit: .month),
                            y: .value(axisTitle, value(for: point)),
                            width: .ratio(0.58)
                        )
                        .foregroundStyle(point.id == focusedPoint?.id ? Color.accentColor : Color.accentColor.opacity(0.34))
                        .clipShape(.rect(cornerRadius: 4))
                        .accessibilityLabel(point.month.formatted(.dateTime.month(.wide)))
                        .accessibilityValue(formattedValue(for: point))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { value in
                            AxisValueLabel(format: .dateTime.month(.narrow))
                            AxisGridLine().foregroundStyle(.clear)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine().foregroundStyle(.tertiary.opacity(0.35))
                            AxisValueLabel {
                                if let number = value.as(Double.self) {
                                    Text(number, format: .number.notation(.compactName))
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    .chartXSelection(value: $selectedMonth)
                    .frame(height: 178)
                }
            }
        }
    }

    private var axisTitle: String {
        switch selectedMetric {
        case .plays: "Plays"
        case .listeningTime: "Minutes"
        case .songs: "Songs"
        case .artists: "Artists"
        }
    }

    private var totalValue: String {
        switch selectedMetric {
        case .plays:
            points.reduce(0) { $0 + $1.plays }.formatted()
        case .listeningTime:
            (points.reduce(0) { $0 + $1.listeningMinutes } * 60).formattedListeningMinutes
        case .songs:
            averageValue.formatted(.number.precision(.fractionLength(0))) + " avg"
        case .artists:
            averageValue.formatted(.number.precision(.fractionLength(0))) + " avg"
        }
    }

    private var averageValue: Double {
        guard !points.isEmpty else { return 0 }
        return points.reduce(0) { $0 + value(for: $1) } / Double(points.count)
    }

    private var focusedPoint: RecapShareTrendPoint? {
        guard let selectedMonth else {
            return points.max { value(for: $0) < value(for: $1) }
        }
        return points.min {
            abs($0.month.timeIntervalSince(selectedMonth)) < abs($1.month.timeIntervalSince(selectedMonth))
        }
    }

    private func value(for point: RecapShareTrendPoint) -> Double {
        switch selectedMetric {
        case .plays: Double(point.plays)
        case .listeningTime: point.listeningMinutes
        case .songs: Double(point.uniqueSongs)
        case .artists: Double(point.uniqueArtists)
        }
    }

    private func formattedValue(for point: RecapShareTrendPoint) -> String {
        switch selectedMetric {
        case .plays:
            return "\(point.plays.formatted()) plays"
        case .listeningTime:
            return "\(Int(point.listeningMinutes.rounded()).formatted()) minutes"
        case .songs:
            return "\(point.uniqueSongs.formatted()) songs"
        case .artists:
            return "\(point.uniqueArtists.formatted()) artists"
        }
    }
}

private struct RecapHeroPoster: View {
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

private struct RecapArtworkCollage: View {
    enum Layout {
        case compact
        case regular
    }

    let artworks: [MPMediaItemArtwork]
    let layout: Layout

    @ViewBuilder
    var body: some View {
        switch artworks.count {
        case 0:
            emptyArtwork
        case 1:
            singleArtwork
        case 2:
            pairedArtwork
        case 3:
            threeArtwork
        default:
            fullCollage
        }
    }

    private var singleArtwork: some View {
        ArtworkView(
            artwork: artworks.first,
            size: layout == .regular ? CGSize(width: 224, height: 224) : CGSize(width: 190, height: 190),
            cornerRadius: layout == .regular ? 30 : 26
        )
        .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 14)
        .recapCollageFrame(height: collageHeight, label: "Recap album artwork")
    }

    private var pairedArtwork: some View {
        ZStack {
            ForEach(artworks.prefix(2).enumerated(), id: \.offset) { index, artwork in
                ArtworkView(
                    artwork: artwork,
                    size: layout == .regular ? CGSize(width: 184, height: 184) : CGSize(width: 150, height: 150),
                    cornerRadius: layout == .regular ? 26 : 22
                )
                .rotationEffect(.degrees(index == 0 ? -5 : 5))
                .offset(x: index == 0 ? pairedOffset : -pairedOffset)
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 12)
            }
        }
        .recapCollageFrame(height: collageHeight, label: "Two recap album artworks")
    }

    private var threeArtwork: some View {
        ZStack {
            ForEach(artworks.dropFirst().prefix(2).enumerated(), id: \.offset) { index, artwork in
                ArtworkView(
                    artwork: artwork,
                    size: layout == .regular ? CGSize(width: 146, height: 146) : CGSize(width: 116, height: 116),
                    cornerRadius: layout == .regular ? 22 : 18
                )
                .rotationEffect(.degrees(index == 0 ? -8 : 8))
                .offset(x: index == 0 ? threeArtworkOffset : -threeArtworkOffset, y: 22)
                .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 8)
            }
            ArtworkView(
                artwork: artworks.first,
                size: mainArtworkSize,
                cornerRadius: layout == .regular ? 28 : 24
            )
            .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 14)
        }
        .recapCollageFrame(height: collageHeight, label: "Three recap album artworks")
    }

    private var fullCollage: some View {
        ZStack {
            ForEach(sideArtworks.enumerated(), id: \.offset) { index, artwork in
                ArtworkView(artwork: artwork, size: sideArtworkSize(for: index), cornerRadius: sideArtworkCornerRadius(for: index))
                    .rotationEffect(.degrees(sideArtworkRotation(for: index)))
                    .offset(sideArtworkOffset(for: index))
                    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 8)
                    .zIndex(Double(index))
            }
            ArtworkView(artwork: artworks.first, size: mainArtworkSize, cornerRadius: layout == .regular ? 28 : 24)
                .rotationEffect(.degrees(-1.5))
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 16)
                .zIndex(20)
        }
        .recapCollageFrame(height: collageHeight, label: "Recap album artwork collage")
    }

    private var collageHeight: CGFloat { layout == .regular ? 282 : 228 }
    private var pairedOffset: CGFloat { layout == .regular ? -66 : -52 }
    private var threeArtworkOffset: CGFloat { layout == .regular ? -142 : -104 }

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
        .recapCollageFrame(height: collageHeight, label: "No recap artwork yet")
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

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
                        .font(.system(size: isRegularWidth ? 36 : 34, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Image(systemName: "chevron.down")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            navigationButton(systemImage: "chevron.right", label: "Next recap", isEnabled: canSelectNext, action: onSelectNext)
        }
        .accessibilityLabel("Recap period")
    }

    private var selectedPeriodTitle: String {
        isYearSelected ? String(selectedYear) : Self.fullMonthFormatter.string(from: selectedMonthStart)
    }

    @ViewBuilder
    private func navigationButton(systemImage: String, label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)

        if #available(iOS 26.0, *) {
            button
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            button
                .background(.ultraThinMaterial, in: Circle())
        }
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
            ForEach(songs.enumerated(), id: \.element.id) { index, song in
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
        .playCountPushedTitleDisplayMode()
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
            ForEach(groups.enumerated(), id: \.element.id) { index, group in
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
        .playCountPushedTitleDisplayMode()
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

private struct RecapFullGainersView: View {
    let category: RecapGainerCategory
    let songs: [MonthlyRecap.MovementSong]
    let albums: [MonthlyRecap.MovementGroup]
    let artists: [MonthlyRecap.MovementGroup]
    @ObservedObject var manager: MediaLibraryManager
    let recapContext: RecapDrilldownContext

    var body: some View {
        List {
            Section {
                RecapGainerBarChart(items: chartItems)
                    .frame(height: max(220, CGFloat(chartItems.count) * 34))
                    .padding(.vertical, 8)
            } header: {
                Text("Additional Plays")
            } footer: {
                Text("Bar length represents plays added during this recap period. Rank movement appears in the details below.")
            }

            Section("Rank Movement") {
            switch category {
            case .songs:
                ForEach(songs.prefix(10)) { song in
                    if let item = manager.song(withPersistentID: song.id)
                        ?? manager.song(matchingTitle: song.title, artist: song.artist) {
                        NavigationLink {
                            SongInfoView(song: item, manager: manager, recapContext: recapContext)
                        } label: {
                            RecapMovementRow(song: song)
                        }
                    } else {
                        RecapMovementRow(song: song)
                    }
                }
            case .albums:
                ForEach(albums.prefix(10)) { group in
                    if let item = resolvedAlbum(group) {
                        NavigationLink {
                            AlbumInfoView(album: item, manager: manager, recapContext: recapContext)
                        } label: {
                            RecapGroupMovementRow(group: group, systemImage: "rectangle.stack.fill")
                        }
                    } else {
                        RecapGroupMovementRow(group: group, systemImage: "rectangle.stack.fill")
                    }
                }
            case .artists:
                ForEach(artists.prefix(10)) { group in
                    if let item = resolvedArtist(group) {
                        NavigationLink {
                            ArtistInfoView(artist: item, manager: manager, recapContext: recapContext)
                        } label: {
                            RecapGroupMovementRow(group: group, systemImage: "person.fill")
                        }
                    } else {
                        RecapGroupMovementRow(group: group, systemImage: "person.fill")
                    }
                }
            }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .navigationTitle("Top 10 \(category.rawValue) Gainers")
        .playCountPushedTitleDisplayMode()
        .toolbar(.visible, for: .navigationBar)
    }

    private var chartItems: [RecapGainerChartItem] {
        switch category {
        case .songs:
            songs.prefix(10).map {
                RecapGainerChartItem(id: "song-\($0.id)", title: $0.title, playDelta: $0.playDelta, rankChange: $0.rankChange)
            }
        case .albums:
            albums.prefix(10).map {
                RecapGainerChartItem(id: "album-\($0.id)", title: $0.title, playDelta: $0.playDelta, rankChange: $0.rankChange)
            }
        case .artists:
            artists.prefix(10).map {
                RecapGainerChartItem(id: "artist-\($0.id)", title: $0.title, playDelta: $0.playDelta, rankChange: $0.rankChange)
            }
        }
    }

    private func resolvedAlbum(_ group: MonthlyRecap.MovementGroup) -> TopAlbum? {
        if let id = UInt64(group.id), let item = manager.album(withPersistentID: id) {
            return item
        }
        return manager.album(matchingTitle: group.title, artist: group.subtitle)
    }

    private func resolvedArtist(_ group: MonthlyRecap.MovementGroup) -> TopArtist? {
        if let id = UInt64(group.id), let item = manager.artist(withPersistentID: id) {
            return item
        }
        return manager.artist(matchingName: group.title)
    }
}

private struct RecapGainerChartItem: Identifiable {
    let id: String
    let title: String
    let playDelta: Int
    let rankChange: Int
}

private struct RecapGainerBarChart: View {
    let items: [RecapGainerChartItem]

    var body: some View {
        Chart(items) { item in
            BarMark(
                x: .value("Additional plays", item.playDelta),
                y: .value("Item", item.id)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.62), Color.accentColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(.rect(cornerRadius: 5))
            .annotation(position: .trailing, spacing: 5) {
                Text("+\(item.playDelta)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(item.title)
            .accessibilityValue("Added \(item.playDelta) plays and moved up \(item.rankChange) ranks")
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartYScale(domain: items.map(\.id))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let id = value.as(String.self), let title = titlesByID[id] {
                        Text(title)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var titlesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.title) })
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
        .playCountPushedTitleDisplayMode()
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

private struct RecapGroupMovementRow: View {
    let group: MonthlyRecap.MovementGroup
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: group.artwork, size: CGSize(width: 58, height: 58), cornerRadius: systemImage == "person.fill" ? 29 : 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title).font(.headline).lineLimit(1)
                Text(group.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text("#\(group.previousRank ?? group.currentRank) to #\(group.currentRank)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Label("\(group.rankChange)", systemImage: "arrow.up")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                    .accessibilityLabel("Up \(group.rankChange) ranks")
                Text("+\(group.playDelta) plays").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.vertical, 9)
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

private struct RecapMonthlyMilestoneMoment: Identifiable {
    let month: Date
    let milestones: [RecapMilestone]

    var id: Date { month }
}

private struct RecapMonthlyMilestoneStrip: View {
    let moments: [RecapMonthlyMilestoneMoment]
    let onSelectMonth: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Milestone Moments")
                .font(.title3.weight(.semibold))

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(moments) { moment in
                        Button {
                            onSelectMonth(moment.month)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(moment.month.formatted(.dateTime.month(.wide)))
                                    .font(.headline)
                                HStack(spacing: -5) {
                                    ForEach(moment.milestones.prefix(3)) { milestone in
                                        MilestoneBadge(milestone: milestone, size: 34)
                                    }
                                }
                                Text("\(moment.milestones.count) unlocked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 132, alignment: .leading)
                            .padding(12)
                            .playCountCardSurface(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "\(moment.month.formatted(.dateTime.month(.wide))), \(moment.milestones.count) milestones unlocked"
                        )
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
        }
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
                }
            }
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
        .playCountPushedTitleDisplayMode()
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

private struct RecapWeeklyInsightSection: View {
    let comparison: WeeklyRecapComparison
    let artwork: MPMediaItemArtwork?

    private var current: WeeklyRecapInsight { comparison.current }

    private var periodTitle: String {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 6, to: current.weekStart) ?? current.weekStart
        return "\(current.weekStart.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This Week")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(periodTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            RecapSurface {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 0) {
                        RecapSummaryItem(
                            title: "Plays",
                            value: current.totalPlayDelta.formatted(),
                            systemImage: "play.fill"
                        )
                        Divider().padding(.vertical, 8)
                        RecapSummaryItem(
                            title: "Time",
                            value: current.totalListeningDuration.formattedListeningMinutes,
                            systemImage: "clock.fill"
                        )
                        Divider().padding(.vertical, 8)
                        RecapSummaryItem(
                            title: "Last Week",
                            value: comparison.previous?.totalPlayDelta.formatted() ?? "—",
                            systemImage: "arrow.left.arrow.right"
                        )
                    }

                    if let song = current.topSong {
                        Divider()
                        HStack(spacing: 11) {
                            ArtworkView(
                                artwork: artwork,
                                size: CGSize(width: 48, height: 48),
                                cornerRadius: 10
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Leading This Week")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(song.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            MetricBadge(text: "+\(song.playDelta)")
                        }
                    } else {
                        Text(baselineMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if comparison.history.count > 1 {
                RecapWeeklyHistoryChart(
                    insights: comparison.history,
                    currentWeekStart: comparison.current.weekStart
                )
            }
        }
    }

    private var baselineMessage: String {
        if current.snapshotCount == 0 {
            return "Open PlayCount after listening to begin weekly insights."
        }
        return "This week's baseline is set. New listening will appear here without guessing about earlier activity."
    }
}

private struct RecapWeeklyHistoryChart: View {
    let insights: [WeeklyRecapInsight]
    let currentWeekStart: Date

    private var displayedInsights: [WeeklyRecapInsight] {
        WeeklyRecapComparison.measuredHistory(
            from: insights,
            inMonthContaining: currentWeekStart
        )
    }

    private var averageMinutes: Double {
        guard !displayedInsights.isEmpty else { return 0 }
        return displayedInsights.reduce(0) { $0 + $1.totalListeningDuration / 60 }
            / Double(displayedInsights.count)
    }

    var body: some View {
        RecapSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Minutes by Week")
                        .font(.headline)
                    Spacer()
                    Text(
                        displayedInsights.count == 1
                            ? "1 tracked week"
                            : "\(displayedInsights.count) tracked weeks"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Chart {
                    ForEach(displayedInsights, id: \.weekStart) { insight in
                        BarMark(
                            x: .value(
                                "Week",
                                insight.weekStart.formatted(.dateTime.month(.abbreviated).day())
                            ),
                            y: .value("Minutes", insight.totalListeningDuration / 60),
                            width: .ratio(0.52)
                        )
                        .foregroundStyle(
                            insight.weekStart == currentWeekStart
                                ? Color.accentColor
                                : Color.accentColor.opacity(0.36)
                        )
                        .accessibilityLabel(
                            (insight.weekStart == currentWeekStart ? "Current week, " : "")
                                + insight.weekStart.formatted(.dateTime.month(.wide).day())
                        )
                        .accessibilityValue(
                            "\(Int((insight.totalListeningDuration / 60).rounded())) minutes"
                        )
                    }
                    RuleMark(y: .value("Average", averageMinutes))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption2)
                        AxisTick().foregroundStyle(.tertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.tertiary.opacity(0.45))
                        AxisValueLabel {
                            if let minutes = value.as(Double.self) {
                                Text(minutes, format: .number.notation(.compactName))
                            }
                        }
                        .font(.caption2)
                    }
                }
                .frame(height: 126)
                .accessibilityLabel("Weekly listening history in minutes")
            }
        }
    }
}

private struct RecapMilestonesSection: View {
    let displayedMilestones: [RecapMilestone]
    let allMilestones: [RecapMilestone]
    let periodLabel: String
    let showsFullCollection: Bool
    let showsUpcomingMilestones: Bool
    @State private var isShowingAllMilestones = false

    private var visibleMilestones: [RecapMilestone] {
        showsFullCollection
            ? MilestoneCollectionPresentation.visibleMilestones(from: displayedMilestones)
            : displayedMilestones
    }

    private var featuredMilestones: [RecapMilestone] {
        showsFullCollection
            ? MilestoneCollectionPresentation.featuredMilestones(from: displayedMilestones, limit: 3)
            : displayedMilestones
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Milestones")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(periodLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if showsFullCollection && visibleMilestones.count > featuredMilestones.count {
                    Button {
                        isShowingAllMilestones = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("View All")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            MilestoneShelf {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(featuredMilestones) { milestone in
                            MilestoneBadgeTile(
                                milestone: milestone,
                                badgeSize: 76,
                                series: MilestoneCollectionPresentation.pathMilestones(
                                    kind: milestone.kind,
                                    all: allMilestones,
                                    displayed: displayedMilestones,
                                    includesUpcoming: showsUpcomingMilestones
                                )
                            )
                            .frame(width: 108)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $isShowingAllMilestones) {
            RecapMilestonesGallery(milestones: allMilestones)
        }
    }
}

struct MilestoneBadgeTile: View {
    let milestone: RecapMilestone
    let badgeSize: CGFloat
    let series: [RecapMilestone]
    @State private var isShowingPath = false

    init(milestone: RecapMilestone, badgeSize: CGFloat, series: [RecapMilestone]? = nil) {
        self.milestone = milestone
        self.badgeSize = badgeSize
        self.series = series ?? [milestone]
    }

    var body: some View {
        Button {
            isShowingPath = true
        } label: {
            VStack(spacing: 5) {
                MilestoneBadge(
                    milestone: milestone,
                    size: badgeSize,
                    showsProgress: milestone.id == nextMilestoneID
                )

                Text(milestone.title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(milestone.title), \(MilestoneMedalTier(stage: milestone.stage).name) medal, \(milestone.valueLabel). \(milestone.statusLabel)"
        )
        .accessibilityHint("Shows this milestone path")
        .sheet(isPresented: $isShowingPath) {
            MilestonePathSheet(selected: milestone, milestones: series)
        }
        .onAppear {
            if MilestonePreview.pathID == milestone.id {
                isShowingPath = true
            }
        }
    }

    private var nextMilestoneID: String? {
        series.sorted { $0.targetValue < $1.targetValue }.first(where: { !$0.isEarned })?.id
    }
}

struct MilestoneBadge: View {
    let milestone: RecapMilestone
    let size: CGFloat
    var showsProgress = false

    var body: some View {
        ZStack {
            GlassMilestoneMedal(
                tier: MilestonePreview.tierOverride ?? MilestoneMedalTier(stage: milestone.stage),
                systemImage: milestone.systemImage,
                isLocked: !milestone.isEarned && !MilestonePreview.previewsUnlocked,
                size: size
            )

            if showsProgress && !milestone.isEarned {
                Circle()
                    .trim(from: 0, to: milestone.progress)
                    .stroke(
                        MilestoneMedalTier(stage: milestone.stage).glassTint,
                        style: StrokeStyle(lineWidth: max(2.5, size * 0.045), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * 1.08, height: size * 1.08)
                    .offset(y: size * 0.125)
            }
        }
    }
}

private struct GlassMilestoneMedal: View {
    let tier: MilestoneMedalTier
    let systemImage: String
    let isLocked: Bool
    let size: CGFloat

    var body: some View {
        medal
            .saturation(isLocked ? 0 : 1)
            .opacity(isLocked ? 0.38 : 1)
            .blur(radius: isLocked ? 1.1 : 0)
        .frame(width: size, height: size * 1.25, alignment: .bottom)
        .accessibilityHidden(true)
    }

    private var medal: some View {
        ZStack(alignment: .bottom) {
            MilestoneBands(tier: tier, size: size)
                .offset(y: -size * 0.5)

            ZStack {
                if !isLocked, tier.usesAnimatedBackground {
                    MilestoneAnimatedAura(tier: tier, size: size)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .opacity(0.94)
                }

                glassLens(hasAnimatedBackground: !isLocked && tier.usesAnimatedBackground)

                milestoneDepthLayers

                Image(systemName: systemImage)
                    .font(.system(size: size * 0.3, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .frame(width: size, height: size)
        }
        .shadow(color: tier.glassTint.opacity(0.18), radius: size * 0.1, y: size * 0.04)
    }

    @ViewBuilder
    private var milestoneDepthLayers: some View {
        if #available(iOS 26.0, *), !isLocked, tier.depthLayerCount > 0 {
            ForEach(0..<tier.depthLayerCount, id: \.self) { layer in
                Color.clear
                    .frame(
                        width: size * (0.82 - CGFloat(layer) * 0.16),
                        height: size * (0.82 - CGFloat(layer) * 0.16)
                    )
                    .glassEffect(.clear, in: .circle)
                    .opacity(0.52 - Double(layer) * 0.12)
            }
        }
    }

    @ViewBuilder
    private func glassLens(hasAnimatedBackground: Bool) -> some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(
                    isLocked
                        ? .clear.tint(.gray.opacity(0.1))
                        : hasAnimatedBackground
                            ? .clear
                            : .clear.tint(tier.glassTint.opacity(0.34)),
                    in: .circle
                )
        } else {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
                .frame(width: size, height: size)
        }
    }
}

private struct MilestoneBands: View {
    let tier: MilestoneMedalTier
    let size: CGFloat

    var body: some View {
        ZStack {
            MedalBandShape(edge: .leading)
                .fill(tier.bandBaseColor)

            MedalBandShape(edge: .trailing)
                .fill(tier.bandBaseColor)

            ForEach(Array(tier.bandStripeRanges.enumerated()), id: \.offset) { _, stripeRange in
                MedalBandStripeShape(edge: .leading, stripeRange: stripeRange)
                    .fill(tier.bandStripeColor)

                MedalBandStripeShape(edge: .trailing, stripeRange: stripeRange)
                    .fill(tier.bandStripeColor)
            }

            MedalRibbonTexture()
                .mask {
                    ZStack {
                        MedalBandShape(edge: .leading)
                        MedalBandShape(edge: .trailing)
                    }
                }
        }
        .frame(width: size * 1.06, height: size * 0.75)
    }
}

private struct MedalRibbonTexture: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 3.5
            var offset = -size.height
            while offset < size.width + size.height {
                var highlight = Path()
                highlight.move(to: CGPoint(x: offset, y: 0))
                highlight.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                context.stroke(highlight, with: .color(.white.opacity(0.12)), lineWidth: 0.45)

                var shadow = Path()
                shadow.move(to: CGPoint(x: offset + spacing * 0.5, y: 0))
                shadow.addLine(to: CGPoint(x: offset + spacing * 0.5 + size.height, y: size.height))
                context.stroke(shadow, with: .color(.black.opacity(0.08)), lineWidth: 0.35)
                offset += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

private struct MedalBandShape: Shape {
    enum Edge {
        case leading
        case trailing
    }

    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let leadingPoints = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY),
            CGPoint(x: rect.minX + rect.width * 0.66, y: rect.maxY),
            CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY),
        ]
        let points = edge == .leading
            ? leadingPoints
            : leadingPoints.map { CGPoint(x: rect.maxX - ($0.x - rect.minX), y: $0.y) }

        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct MedalBandStripeShape: Shape {
    let edge: MedalBandShape.Edge
    let stripeRange: ClosedRange<CGFloat>

    func path(in rect: CGRect) -> Path {
        let topLeading = rect.minX + rect.width * (0.38 * stripeRange.lowerBound)
        let topTrailing = rect.minX + rect.width * (0.38 * stripeRange.upperBound)
        let bottomLeading = rect.minX + rect.width * (0.34 + 0.32 * stripeRange.lowerBound)
        let bottomTrailing = rect.minX + rect.width * (0.34 + 0.32 * stripeRange.upperBound)
        let leadingPoints = [
            CGPoint(x: topLeading, y: rect.minY),
            CGPoint(x: topTrailing, y: rect.minY),
            CGPoint(x: bottomTrailing, y: rect.maxY),
            CGPoint(x: bottomLeading, y: rect.maxY),
        ]
        let points = edge == .leading
            ? leadingPoints
            : leadingPoints.map { CGPoint(x: rect.maxX - ($0.x - rect.minX), y: $0.y) }

        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct MilestoneAnimatedAura: View {
    let tier: MilestoneMedalTier
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        aura(expanded: expanded)
            .onAppear(perform: updateAnimation)
            .onChange(of: reduceMotion) { updateAnimation() }
            .onDisappear(perform: stopAnimation)
    }

    private func updateAnimation() {
        guard !reduceMotion else {
            stopAnimation()
            return
        }
        guard !expanded else { return }
        withAnimation(.easeInOut(duration: 5.6).repeatForever(autoreverses: true)) {
            expanded = true
        }
    }

    private func stopAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expanded = false
        }
    }

    private func aura(expanded: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: tier.auraColors,
                        center: .center,
                        angle: .degrees(expanded ? 52 : -32)
                    )
                )
                .rotationEffect(.degrees(expanded ? 34 : -28))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.22), tier.glassTint.opacity(0.32), .clear],
                        center: expanded ? .topTrailing : .bottomLeading,
                        startRadius: 0,
                        endRadius: size * 0.46
                    )
                )
                .scaleEffect(expanded ? 0.94 : 0.58)
                .offset(
                    x: expanded ? -size * 0.16 : size * 0.16,
                    y: expanded ? size * 0.12 : -size * 0.12
                )
        }
        .blur(radius: size * 0.035)
        .scaleEffect(expanded ? 1.18 : 1.06)
    }
}

private enum MilestonePreview {
    static var previewsUnlocked: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-PlayCountMedalPreviewUnlocked")
        #else
        false
        #endif
    }

    static var tierOverride: MilestoneMedalTier? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-PlayCountMedalPreviewTier"),
              arguments.indices.contains(flagIndex + 1),
              let stage = Int(arguments[flagIndex + 1]) else {
            return nil
        }
        return MilestoneMedalTier(stage: stage)
        #else
        return nil
        #endif
    }

    static var pathID: String? {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-PlayCountMilestonePreviewPath"),
              arguments.indices.contains(flagIndex + 1) else {
            return nil
        }
        return arguments[flagIndex + 1]
        #else
        return nil
        #endif
    }
}

enum MilestoneMedalTier: Int, CaseIterable {
    case copper
    case bronze
    case silver
    case gold
    case emerald
    case sapphire
    case roseGold
    case platinum
    case legend

    init(stage: Int) {
        self = Self.allCases[min(max(stage, 0), Self.allCases.count - 1)]
    }

    var name: String {
        switch self {
        case .copper: "Copper"
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .emerald: "Emerald"
        case .sapphire: "Sapphire"
        case .roseGold: "Rose Gold"
        case .platinum: "Platinum"
        case .legend: "Legend"
        }
    }

    var glassTint: Color {
        switch self {
        case .copper: .red
        case .bronze: .orange
        case .silver: Color(red: 0.72, green: 0.74, blue: 0.78)
        case .gold: .yellow
        case .emerald: .green
        case .sapphire: Color(red: 0.08, green: 0.27, blue: 0.78)
        case .roseGold: Color(red: 0.86, green: 0.42, blue: 0.35)
        case .platinum: Color(red: 0.82, green: 0.94, blue: 0.91)
        case .legend: .purple
        }
    }

    var auraColors: [Color] {
        switch self {
        case .copper: [.brown, .red, .orange, .brown]
        case .bronze: [.red, .orange, .pink, .red]
        case .silver: [
            Color(red: 0.42, green: 0.44, blue: 0.49),
            Color(red: 0.88, green: 0.9, blue: 0.94),
            .white,
            Color(red: 0.42, green: 0.44, blue: 0.49)
        ]
        case .gold: [.orange, .yellow, .pink, .orange]
        case .emerald: [.green, .mint, .cyan, .green]
        case .sapphire: [
            Color(red: 0.03, green: 0.08, blue: 0.34),
            Color(red: 0.06, green: 0.25, blue: 0.86),
            Color(red: 0.3, green: 0.55, blue: 1),
            Color(red: 0.03, green: 0.08, blue: 0.34)
        ]
        case .roseGold: [
            Color(red: 0.48, green: 0.16, blue: 0.13),
            Color(red: 0.9, green: 0.45, blue: 0.37),
            Color(red: 1, green: 0.72, blue: 0.57),
            Color(red: 0.48, green: 0.16, blue: 0.13)
        ]
        case .platinum: [
            Color(red: 0.42, green: 0.5, blue: 0.55),
            Color(red: 0.86, green: 0.96, blue: 0.94),
            .white,
            Color(red: 0.42, green: 0.5, blue: 0.55)
        ]
        case .legend: [.purple, .blue, .pink, .purple]
        }
    }

    var usesAnimatedBackground: Bool {
        switch self {
        case .copper, .bronze, .silver, .gold, .emerald, .sapphire: false
        case .roseGold, .platinum, .legend: true
        }
    }

    var depthLayerCount: Int {
        switch self {
        case .copper, .bronze, .silver, .gold, .emerald, .sapphire: 0
        case .roseGold: 1
        case .platinum: 1
        case .legend: 2
        }
    }

    var bandBaseColor: Color {
        switch self {
        case .copper: .brown
        case .bronze: .brown
        case .silver: Color(red: 0.3, green: 0.31, blue: 0.35)
        case .gold: .red
        case .emerald: .green
        case .sapphire: Color(red: 0.02, green: 0.09, blue: 0.38)
        case .roseGold: Color(red: 0.45, green: 0.14, blue: 0.12)
        case .platinum: Color(red: 0.48, green: 0.54, blue: 0.58)
        case .legend: .purple
        }
    }

    var bandStripeColor: Color {
        switch self {
        case .copper: .red
        case .bronze: .orange
        case .silver: Color(red: 0.9, green: 0.92, blue: 0.96)
        case .gold: .yellow
        case .emerald: .mint
        case .sapphire: Color(red: 0.28, green: 0.56, blue: 1)
        case .roseGold: Color(red: 1, green: 0.62, blue: 0.48)
        case .platinum: Color(red: 0.86, green: 0.97, blue: 0.94)
        case .legend: .cyan
        }
    }

    var bandStripeRanges: [ClosedRange<CGFloat>] {
        switch self {
        case .copper: [0.46...0.54]
        case .bronze: [0.42...0.58]
        case .silver: [0.2...0.32, 0.68...0.8]
        case .gold: [0.34...0.66]
        case .emerald: [0.16...0.26, 0.46...0.54, 0.74...0.84]
        case .sapphire: [0.1...0.2, 0.32...0.42, 0.58...0.68, 0.8...0.9]
        case .roseGold: [0.18...0.3, 0.44...0.56, 0.7...0.82]
        case .platinum: [0.16...0.28, 0.36...0.64, 0.72...0.84]
        case .legend: [0.06...0.16, 0.3...0.4, 0.6...0.7, 0.84...0.94]
        }
    }

}

struct MilestoneShelf<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if #available(iOS 26.0, *) {
                    Color.clear
                        .glassEffect(
                            .regular.tint(.white.opacity(0.025)),
                            in: .rect(cornerRadius: 24)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
    }
}

struct MilestonePathSheet: View {
    let selected: RecapMilestone
    let milestones: [RecapMilestone]
    @Environment(\.dismiss) private var dismiss

    private var orderedMilestones: [RecapMilestone] {
        milestones.sorted { $0.targetValue < $1.targetValue }
    }

    private var nextMilestone: RecapMilestone? {
        orderedMilestones.first { !$0.isEarned }
    }

    private var focusID: String? {
        nextMilestone?.id ?? orderedMilestones.last?.id
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(orderedMilestones) { milestone in
                            MilestonePathTile(
                                milestone: milestone,
                                isNext: milestone.id == nextMilestone?.id
                            )
                            .id(milestone.id)
                            .containerRelativeFrame(.horizontal, count: 3, span: 2, spacing: 18)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .task(id: focusID) {
                    guard let focusID else { return }
                    await Task.yield()
                    proxy.scrollTo(focusID, anchor: .center)
                }
            }
            .navigationTitle(pathTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var pathTitle: String {
        switch selected.kind {
        case .songPlays: "\(selected.detail) Plays"
        case .albumPlays: "\(selected.detail) Track Plays"
        case .artistPlays: "\(selected.detail) Plays"
        case .songListeningTime, .albumListeningTime, .artistListeningTime,
             .songBond, .albumHome, .artistEra:
            "Time With \(selected.detail)"
        case .artistDiscovery, .songDiscovery, .listeningTime:
            selected.kind.collectionTitle
        }
    }
}

private struct MilestonePathTile: View {
    let milestone: RecapMilestone
    let isNext: Bool

    var body: some View {
        VStack(spacing: 10) {
            MilestoneBadge(milestone: milestone, size: 104, showsProgress: isNext)

            Text(milestone.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            if milestone.isEarned {
                Text(milestone.achievementDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            } else if isNext {
                Text("Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250, alignment: .top)
        .padding(16)
        .background(.quaternary.opacity(0.38), in: .rect(cornerRadius: 22))
        .clipShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isNext ? milestone.valueLabel : milestone.statusLabel)
    }
}

private struct RecapMilestonesGallery: View {
    let milestones: [RecapMilestone]
    @Environment(\.dismiss) private var dismiss

    private var milestoneGroups: [[RecapMilestone]] {
        MilestoneCollectionPresentation.groups(from: milestones)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    ForEach(Array(milestoneGroups.enumerated()), id: \.offset) { _, group in
                        if let first = group.first {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(first.kind.collectionTitle)
                                    .font(.title3.weight(.semibold))

                                ScrollView(.horizontal) {
                                    LazyHStack(alignment: .top, spacing: 14) {
                                        ForEach(MilestoneCollectionPresentation.visibleMilestones(from: group)) { milestone in
                                        MilestoneBadgeTile(
                                            milestone: milestone,
                                            badgeSize: 82,
                                            series: group
                                        )
                                        .frame(width: 112)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
            .navigationTitle("Milestones")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct RecapTrackingCoverageNotice: View {
    let playCount: Int
    let listeningDuration: TimeInterval

    var body: some View {
        RecapSurface {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Includes activity from an untracked interval")
                        .font(.callout.weight(.semibold))
                    Text("\(playCount.formatted()) plays · \(listeningDuration.formattedListeningMinutes) couldn't be assigned to a specific month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
