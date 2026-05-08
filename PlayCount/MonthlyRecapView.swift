import CoreImage.CIFilterBuiltins
import MediaPlayer
import SwiftUI

struct MonthlyRecapView: View {
    @ObservedObject var manager: MediaLibraryManager
    @State private var selectedMonthStart: Date?
    @State private var isShowingYearAggregate = false
    @State private var monthTransitionEdge: Edge = .trailing
    @State private var monthDragOffset: CGFloat = 0
    @State private var isUsingYearlyBreakdownStrip = false

    #if DEBUG
    @State private var reminderStatusMessage: String?
    #endif

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

    private var heroArtwork: MPMediaItemArtwork? {
        artworkHighlights.first
    }

    private func resolvedArtwork(for song: MonthlyRecap.RankedSong) -> MPMediaItemArtwork? {
        song.artwork
            ?? allLibrarySongs.first(where: { $0.id == song.id })?.artwork
            ?? allLibrarySongs.first(where: {
                $0.title.normalizedRecapArtworkKey == song.title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == song.artist.normalizedRecapArtworkKey
            })?.artwork
            ?? albumArtwork(title: song.albumTitle, artist: song.artist)
    }

    private func resolvedArtwork(for song: MonthlyRecap.MovementSong) -> MPMediaItemArtwork? {
        song.artwork
            ?? allLibrarySongs.first(where: { $0.id == song.id })?.artwork
            ?? allLibrarySongs.first(where: {
                $0.title.normalizedRecapArtworkKey == song.title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == song.artist.normalizedRecapArtworkKey
            })?.artwork
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
        allLibrarySongs.first { $0.id == song.id }
            ?? allLibrarySongs.first {
                $0.title.normalizedRecapArtworkKey == song.title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == song.artist.normalizedRecapArtworkKey
            }
    }

    private func resolvedTopSong(for song: MonthlyRecap.MovementSong) -> TopSong? {
        allLibrarySongs.first { $0.id == song.id }
            ?? allLibrarySongs.first {
                $0.title.normalizedRecapArtworkKey == song.title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == song.artist.normalizedRecapArtworkKey
            }
    }

    private func resolvedTopAlbum(for group: MonthlyRecap.RankedGroup) -> TopAlbum? {
        if let id = UInt64(group.id),
           let album = manager.album(withPersistentID: id) {
            return album
        }

        return allLibraryAlbums.first {
            $0.title.normalizedRecapArtworkKey == group.title.normalizedRecapArtworkKey &&
                $0.artist.normalizedRecapArtworkKey == group.subtitle.normalizedRecapArtworkKey
        }
    }

    private func resolvedTopArtist(for group: MonthlyRecap.RankedGroup) -> TopArtist? {
        if let id = UInt64(group.id),
           let artist = manager.artist(withPersistentID: id) {
            return artist
        }

        return allLibraryArtists.first {
            $0.name.normalizedRecapArtworkKey == group.title.normalizedRecapArtworkKey
        }
    }

    private var allLibrarySongs: [TopSong] {
        manager.librarySongs + manager.topSongs
    }

    private var allLibraryAlbums: [TopAlbum] {
        manager.libraryAlbums + manager.topAlbums
    }

    private var allLibraryArtists: [TopArtist] {
        manager.libraryArtists + manager.topArtists
    }

    private func albumArtwork(title: String, artist: String) -> MPMediaItemArtwork? {
        allLibraryAlbums.first(where: {
            $0.title.normalizedRecapArtworkKey == title.normalizedRecapArtworkKey &&
                $0.artist.normalizedRecapArtworkKey == artist.normalizedRecapArtworkKey
        })?.artwork
            ?? allLibrarySongs.first(where: {
                $0.albumTitle.normalizedRecapArtworkKey == title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == artist.normalizedRecapArtworkKey
            })?.artwork
    }

    private func artistArtwork(name: String) -> MPMediaItemArtwork? {
        allLibraryArtists.first(where: {
            $0.name.normalizedRecapArtworkKey == name.normalizedRecapArtworkKey
        })?.artwork
            ?? allLibrarySongs.first(where: {
                $0.artist.normalizedRecapArtworkKey == name.normalizedRecapArtworkKey
            })?.artwork
    }

    private func appendUniqueArtwork(
        key: String,
        artwork: MPMediaItemArtwork?,
        seen: inout Set<String>,
        result: inout [MPMediaItemArtwork]
    ) {
        guard result.count < 4,
              let artwork,
              !key.isEmpty else {
            return
        }

        let visualKey = artwork.recapVisualDedupKey
        guard !seen.contains(key),
              visualKey.map({ !seen.contains($0) }) ?? true else {
            return
        }

        seen.insert(key)
        if let visualKey {
            seen.insert(visualKey)
        }
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
                        artworks: artworkHighlights,
                        leadingSong: recap.topSongs.first,
                        leadingSongArtwork: recap.topSongs.first.flatMap(resolvedArtwork(for:)),
                        selectedYear: selectedRecapYear,
                        months: selectedYearMonths,
                        isYearSelected: isShowingYearAggregate,
                        selectedMonthStart: selectedMonthStartOrCurrent,
                        onSelectYear: selectYearAggregate,
                        onSelectMonth: { selectMonth($0) }
                    )

                    if recap.hasActivity {
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
                            if hasYearlyMonthlyHighlights {
                                yearlyMonthlyBreakdownSection
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
                    } else {
                        baselineSection
                    }

                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 36)
                .offset(x: monthDragDisplayOffset)
                .id(selectedMonthStartOrCurrent)
                .transition(monthContentTransition)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            manager.refreshForRecapSequence(reason: .manualRefresh)
        }
        .background(RecapBackground(artwork: heroArtwork))
        .overlay(alignment: .topTrailing) {
            floatingYearPicker
                .padding(.top, 8)
                .padding(.trailing, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .animation(.smooth(duration: 0.26), value: selectedMonthStartOrCurrent)
        .simultaneousGesture(monthSwipeGesture)
        .onAppear {
            syncSelectedMonthIfNeeded()
        }
        .onChange(of: manager.availableRecapMonths) { _, _ in
            syncSelectedMonthIfNeeded()
        }
        .onChange(of: manager.monthlyRecap.monthStart) { _, _ in
            syncSelectedMonthIfNeeded()
        }
    }

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
                    NavigationLink {
                        SongInfoView(song: topSong, manager: manager, recapContext: recapDrilldownContext)
                    } label: {
                        RecapSongRow(song: song, artwork: resolvedArtwork(for: song))
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
                    NavigationLink {
                        SongInfoView(song: topSong, manager: manager, recapContext: recapDrilldownContext)
                    } label: {
                        RecapMovementRow(song: song, artwork: resolvedArtwork(for: song))
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
                    NavigationLink {
                        SongInfoView(song: topSong, manager: manager, recapContext: recapDrilldownContext)
                    } label: {
                        RecapSongRow(song: song, artwork: resolvedArtwork(for: song))
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
                    NavigationLink {
                        AlbumInfoView(album: topAlbum, manager: manager, recapContext: recapDrilldownContext)
                    } label: {
                        RecapGroupRow(group: album, systemImage: "rectangle.stack.fill", artwork: resolvedArtwork(for: album, systemImage: "rectangle.stack.fill"))
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
                    NavigationLink {
                        ArtistInfoView(artist: topArtist, manager: manager, recapContext: recapDrilldownContext)
                    } label: {
                        RecapGroupRow(group: artist, systemImage: "person.fill", artwork: resolvedArtwork(for: artist, systemImage: "person.fill"))
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
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard !isUsingYearlyBreakdownStrip else {
                    monthDragOffset = 0
                    return
                }
                guard abs(horizontal) > 8,
                      abs(horizontal) > abs(vertical) * 1.2 else {
                    return
                }

                monthDragOffset = clampedMonthDragOffset(horizontal)
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                defer {
                    withAnimation(.smooth(duration: 0.22)) {
                        monthDragOffset = 0
                    }
                }

                guard !isUsingYearlyBreakdownStrip else { return }

                guard abs(horizontal) > 64,
                      abs(horizontal) > abs(vertical) * 1.35 else {
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

    private func setYearlyBreakdownScrollActivity(_ isActive: Bool) {
        if isActive {
            isUsingYearlyBreakdownStrip = true
            monthDragOffset = 0
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isUsingYearlyBreakdownStrip = false
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
    let onSelectYear: () -> Void
    let onSelectMonth: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RecapArtworkStack(artworks: artworks)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(monthTitle)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)

                RecapPeriodStrip(
                    selectedYear: selectedYear,
                    months: months,
                    isYearSelected: isYearSelected,
                    selectedMonthStart: selectedMonthStart,
                    onSelectYear: onSelectYear,
                    onSelectMonth: onSelectMonth
                )

                RecapSummaryBar(recap: recap)
            }

            if let leadingSong {
                RecapHeroSpotlight(song: leadingSong, artwork: leadingSongArtwork)
            }
        }
        .padding(.top, 4)
    }
}

private struct RecapPeriodStrip: View {
    let selectedYear: Int
    let months: [Date]
    let isYearSelected: Bool
    let selectedMonthStart: Date
    let onSelectYear: () -> Void
    let onSelectMonth: (Date) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                periodChip(
                    title: String(selectedYear),
                    isSelected: isYearSelected,
                    action: onSelectYear
                )

                ForEach(months, id: \.timeIntervalSinceReferenceDate) { month in
                    periodChip(
                        title: Self.monthFormatter.string(from: month),
                        isSelected: !isYearSelected && Calendar.current.isDate(month, equalTo: selectedMonthStart, toGranularity: .month)
                    ) {
                        onSelectMonth(month)
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Recap period")
    }

    private func periodChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, isSelected ? 11 : 9)
                .frame(height: 28)
                .background {
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.primary.opacity(0.10) : Color.primary.opacity(0.045))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLL"
        return formatter
    }()
}

private struct RecapArtworkStack: View {
    let artworks: [MPMediaItemArtwork]
    @State private var isAnimated = false
    @State private var topArtworkID = 0

    var body: some View {
        ZStack {
            if let mainArtwork = artworks.first {
                ZStack {
                    ForEach(Array(sideArtworks.enumerated()), id: \.element.id) { index, sideArtwork in
                        Button {
                            bringArtworkToTop(sideArtwork.id)
                        } label: {
                            ArtworkView(
                                artwork: sideArtwork.artwork,
                                size: CGSize(width: sideArtworkSize(for: index), height: sideArtworkSize(for: index)),
                                cornerRadius: 18
                            )
                        }
                        .buttonStyle(RecapArtworkButtonStyle())
                        .shadow(color: .black.opacity(0.17), radius: 13, x: 0, y: 9)
                        .rotationEffect(.degrees(sideArtworkRotation(for: index) + (isAnimated ? sideAnimationRotation(for: index) : 0)))
                        .offset(sideArtworkOffset(for: index, animated: isAnimated))
                        .zIndex(zIndex(for: sideArtwork.id, defaultZIndex: Double(index)))
                        .accessibilityLabel("Bring album cover forward")
                    }

                    Button {
                        bringArtworkToTop(0)
                    } label: {
                        ArtworkView(
                            artwork: mainArtwork,
                            size: CGSize(width: 212, height: 212),
                            cornerRadius: 28
                        )
                    }
                    .buttonStyle(RecapArtworkButtonStyle())
                    .shadow(color: .black.opacity(0.26), radius: 26, x: 0, y: 18)
                    .rotationEffect(.degrees(-1.5 + (isAnimated ? 0.45 : 0)))
                    .scaleEffect(isAnimated ? 1.015 : 1)
                    .zIndex(zIndex(for: 0, defaultZIndex: 20))
                    .accessibilityLabel("Bring main album cover forward")
                }
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(width: 172, height: 172)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(height: 314)
        .task {
            guard !isAnimated else { return }
            withAnimation(.easeInOut(duration: 4.6).repeatForever(autoreverses: true)) {
                isAnimated = true
            }
        }
        .onChange(of: artworks.count) { _, newCount in
            guard newCount > 0 else {
                topArtworkID = 0
                return
            }
            if !artworks.indices.contains(topArtworkID) {
                topArtworkID = 0
            }
        }
    }

    private struct SideArtwork: Identifiable {
        let id: Int
        let artwork: MPMediaItemArtwork
    }

    private struct RecapArtworkButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }

    private var sideArtworks: [SideArtwork] {
        artworks.enumerated()
            .dropFirst()
            .prefix(3)
            .map { SideArtwork(id: $0.offset, artwork: $0.element) }
    }

    private func bringArtworkToTop(_ id: Int) {
        guard artworks.indices.contains(id) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            topArtworkID = id
        }
    }

    private func zIndex(for id: Int, defaultZIndex: Double) -> Double {
        id == topArtworkID ? 40 : defaultZIndex
    }

    private func sideArtworkRotation(for index: Int) -> Double {
        switch index {
        case 0: return -12
        case 1: return 11
        default: return 4
        }
    }

    private func sideAnimationRotation(for index: Int) -> Double {
        switch index {
        case 0: return -1.4
        case 1: return 1.2
        default: return -0.8
        }
    }

    private func sideArtworkOffset(for index: Int, animated: Bool) -> CGSize {
        let float = animated ? sideFloat(for: index) : .zero
        switch index {
        case 0:
            return CGSize(width: -126 + float.width, height: 72 + float.height)
        case 1:
            return CGSize(width: 126 + float.width, height: 76 + float.height)
        default:
            return CGSize(width: float.width, height: 118 + float.height)
        }
    }

    private func sideFloat(for index: Int) -> CGSize {
        switch index {
        case 0:
            return CGSize(width: -5, height: 5)
        case 1:
            return CGSize(width: 5, height: -4)
        default:
            return CGSize(width: 0, height: 6)
        }
    }

    private func sideArtworkSize(for index: Int) -> CGFloat {
        index == 2 ? 96 : 112
    }
}

private struct RecapHeroSpotlight: View {
    let song: MonthlyRecap.RankedSong
    let artwork: MPMediaItemArtwork?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(
                artwork: artwork ?? song.artwork,
                size: CGSize(width: 52, height: 52),
                cornerRadius: 10
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
        .recapTileSurface(cornerRadius: 16, tintOpacity: 0.07)
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
            RecapSummaryItem(title: "Songs", value: "\(recap.topSongs.count)", systemImage: "music.note")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .recapTileSurface(cornerRadius: 16, tintOpacity: 0.06)
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
        let allSongs = manager.librarySongs + manager.topSongs
        return allSongs.first { $0.id == song.id }
            ?? allSongs.first {
                $0.title.normalizedRecapArtworkKey == song.title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == song.artist.normalizedRecapArtworkKey
            }
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

        let allAlbums = manager.libraryAlbums + manager.topAlbums
        return allAlbums.first {
            $0.title.normalizedRecapArtworkKey == group.title.normalizedRecapArtworkKey &&
                $0.artist.normalizedRecapArtworkKey == group.subtitle.normalizedRecapArtworkKey
        }
    }

    private func resolvedTopArtist(for group: MonthlyRecap.RankedGroup) -> TopArtist? {
        if let id = UInt64(group.id),
           let artist = manager.artist(withPersistentID: id) {
            return artist
        }

        let allArtists = manager.libraryArtists + manager.topArtists
        return allArtists.first {
            $0.name.normalizedRecapArtworkKey == group.title.normalizedRecapArtworkKey
        }
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
        let allSongs = manager.librarySongs + manager.topSongs
        return allSongs.first { $0.id == song.id }
            ?? allSongs.first {
                $0.title.normalizedRecapArtworkKey == song.title.normalizedRecapArtworkKey &&
                    $0.artist.normalizedRecapArtworkKey == song.artist.normalizedRecapArtworkKey
            }
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
        .recapTileSurface(cornerRadius: 16, tintOpacity: 0.08)
    }
}

private struct RecapMiniInsight: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .recapTileSurface(cornerRadius: 16, tintOpacity: 0.06)
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
        .recapTileSurface(cornerRadius: 20, tintOpacity: 0.08)
    }
}

private struct RecapGlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 10) {
                    content
                }
            }
        } else {
            VStack(spacing: 10) {
                content
            }
        }
    }
}

private struct RecapTileSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tintOpacity: Double

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear.tint(Color.accentColor.opacity(tintOpacity * 0.45)), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06))
                }
        }
    }
}

private extension View {
    func recapTileSurface(cornerRadius: CGFloat, tintOpacity: Double) -> some View {
        modifier(RecapTileSurfaceModifier(cornerRadius: cornerRadius, tintOpacity: tintOpacity))
    }
}

private struct RecapBackground: View {
    let artwork: MPMediaItemArtwork?

    var body: some View {
        ZStack {
            if let gradientColors {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(.systemGroupedBackground)
            }

            Color(.systemBackground)
                .opacity(0.18)
        }
        .ignoresSafeArea()
    }

    private var gradientColors: [Color]? {
        guard let components = artwork?.recapAverageColorComponents() else {
            return nil
        }

        return [
            Color(
                red: darken(components.0, amount: 0.45),
                green: darken(components.1, amount: 0.45),
                blue: darken(components.2, amount: 0.45)
            ),
            Color(
                red: boost(components.0, amount: 0.18),
                green: boost(components.1, amount: 0.18),
                blue: boost(components.2, amount: 0.18)
            ),
            Color(.systemGroupedBackground)
        ]
    }

    private func darken(_ component: Double, amount: Double) -> Double {
        max(component * (1 - amount), 0)
    }

    private func boost(_ component: Double, amount: Double) -> Double {
        min(component + (1 - component) * amount, 1)
    }
}

private enum RecapColorCalculator {
    static let context = CIContext(options: [.workingColorSpace: NSNull()])
    static let cache = NSCache<NSString, RecapArtworkColorBox>()
}

private final class RecapArtworkColorBox {
    let components: (Double, Double, Double)

    init(_ components: (Double, Double, Double)) {
        self.components = components
    }
}

private extension MPMediaItemArtwork {
    var recapVisualDedupKey: String? {
        guard let components = recapAverageColorComponents(maxDimension: 36) else {
            return nil
        }

        let red = Int((components.0 * 24).rounded())
        let green = Int((components.1 * 24).rounded())
        let blue = Int((components.2 * 24).rounded())
        return "visual-\(red)-\(green)-\(blue)"
    }

    func recapAverageColorComponents(maxDimension: CGFloat = 80) -> (Double, Double, Double)? {
        let pixelDimension = Int((maxDimension * UIScreen.main.scale).rounded(.up))
        let cacheKey = "\(ObjectIdentifier(self))-\(pixelDimension)" as NSString

        if let cached = RecapColorCalculator.cache.object(forKey: cacheKey) {
            return cached.components
        }

        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        guard let image = image(at: targetSize),
              let inputImage = CIImage(image: image) else {
            return nil
        }

        let extent = inputImage.extent
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let filter = CIFilter.areaAverage()
        filter.inputImage = inputImage
        filter.extent = extent

        guard let outputImage = filter.outputImage else {
            return nil
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        RecapColorCalculator.context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let components = (
            Double(bitmap[0]) / 255.0,
            Double(bitmap[1]) / 255.0,
            Double(bitmap[2]) / 255.0
        )

        RecapColorCalculator.cache.setObject(RecapArtworkColorBox(components), forKey: cacheKey)
        return components
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
