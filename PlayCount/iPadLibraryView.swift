import SwiftUI

struct iPadLibraryView: View {
    private enum LibraryTab: String, Hashable {
        case dashboard
        case recap
        case search
    }

    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: LibraryTab = .dashboard
    @State private var presentedNowPlayingSong: TopSong?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("All-Time", systemImage: "chart.bar.xaxis", value: LibraryTab.dashboard) {
                activeContent(for: .dashboard) {
                    NavigationStack {
                        iPadAllTimeDashboardView(manager: manager)
                            .navigationTitle("All-Time")
                            .navigationBarTitleDisplayMode(.large)
                            .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                            .toolbar { toolbarContent }
                    }
                }
            }

            Tab("Recap", systemImage: "calendar", value: LibraryTab.recap) {
                activeContent(for: .recap) {
                    NavigationStack {
                        MonthlyRecapView(manager: manager)
                            .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                            .toolbar { toolbarContent }
                    }
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: LibraryTab.search, role: .search) {
                activeContent(for: .search) {
                    NavigationStack {
                        LibrarySearchView(manager: manager)
                            .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                            .toolbar { toolbarContent }
                    }
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            NowPlayingBarView(manager: manager) { state in
                if let song = state.song {
                    presentedNowPlayingSong = song
                }
            }
            .environment(\.colorScheme, colorScheme)
        }
        .sheet(item: $presentedNowPlayingSong) { song in
            NavigationStack {
                SongInfoView(song: song, manager: manager)
            }
        }
        .onChange(of: manager.nowPlayingState) { _, state in
            guard let state else {
                presentedNowPlayingSong = nil
                return
            }

            if let song = state.song, presentedNowPlayingSong?.id == song.id {
                presentedNowPlayingSong = song
            } else if presentedNowPlayingSong != nil {
                presentedNowPlayingSong = state.song
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMonthlyRecap)) { _ in
            selectedTab = .recap
            manager.refreshForRecapSequence(reason: .notificationOpen)
        }
    }

    @ViewBuilder
    private func activeContent<Content: View>(
        for tab: LibraryTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if selectedTab == tab {
            content()
        } else {
            Color.clear
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if manager.isLoading {
                ProgressView()
            }
            sortPicker
            refreshButton
        }
    }

    private var sortPicker: some View {
        Menu {
            ForEach(MediaLibraryManager.SortMetric.allCases) { metric in
                Button {
                    manager.sortMetric = metric
                } label: {
                    Label(metric.menuTitle, systemImage: metric.systemImageName)
                }
            }
        } label: {
            Image(systemName: manager.sortMetric.systemImageName)
                .accessibilityLabel(Text(manager.sortMetric.toolbarLabel))
                .imageScale(.medium)
        }
    }

    private var refreshButton: some View {
        Button(action: manager.refreshTopItems) {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(manager.isLoading)
    }
}

private struct iPadAllTimeDashboardView: View {
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                iPadDashboardSummaryBar(metrics: summaryMetrics)

                if showsEmptyState {
                    iPadDashboardEmptyState(hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot)
                } else {
                    LazyVGrid(columns: Self.dashboardColumns, alignment: .leading, spacing: 18) {
                        topSongsSection
                        topAlbumsSection
                        topArtistsSection
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .frame(maxWidth: 1180, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.hidden)
    }

    private var showsEmptyState: Bool {
        manager.topSongs.isEmpty && manager.topAlbums.isEmpty && manager.topArtists.isEmpty
    }

    private var summaryMetrics: [iPadDashboardMetric] {
        let summary = manager.librarySummary
        return [
            iPadDashboardMetric(title: "Songs", value: summary.songCount.detailFormatted, systemImage: "music.note"),
            iPadDashboardMetric(title: "Albums", value: summary.albumCount.detailFormatted, systemImage: "rectangle.stack.fill"),
            iPadDashboardMetric(title: "Artists", value: summary.artistCount.detailFormatted, systemImage: "person.2.fill"),
            iPadDashboardMetric(title: "Plays", value: summary.totalPlayCount.detailFormatted, systemImage: "play.fill"),
            iPadDashboardMetric(title: "Time", value: summary.totalListeningDuration.formattedListeningMinutes, systemImage: "clock.fill")
        ]
    }

    private static let dashboardColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 320, maximum: 380), spacing: 18, alignment: .top)
    ]

    private var topSongsSection: some View {
        iPadDashboardSection(
            title: "Top Songs",
            systemImage: "music.note.list",
            totalCount: manager.topSongs.count,
            visibleCount: 6
        ) {
            TopSongsView(
                songs: manager.topSongs,
                sortMetric: manager.sortMetric,
                hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                manager: manager
            )
            .navigationTitle("Top Songs")
        } content: {
            ForEach(Array(manager.topSongs.prefix(6).enumerated()), id: \.element.id) { index, song in
                NavigationLink {
                    SongInfoView(song: song, manager: manager)
                } label: {
                    SongRow(song: song, sortMetric: manager.sortMetric, rank: index + 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topAlbumsSection: some View {
        iPadDashboardSection(
            title: "Top Albums",
            systemImage: "rectangle.stack.fill",
            totalCount: manager.topAlbums.count,
            visibleCount: 6
        ) {
            TopAlbumsView(
                albums: manager.topAlbums,
                sortMetric: manager.sortMetric,
                hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                manager: manager
            )
            .navigationTitle("Top Albums")
        } content: {
            ForEach(Array(manager.topAlbums.prefix(6).enumerated()), id: \.element.id) { index, album in
                NavigationLink {
                    AlbumInfoView(album: album, manager: manager)
                } label: {
                    AlbumRow(album: album, sortMetric: manager.sortMetric, rank: index + 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var topArtistsSection: some View {
        iPadDashboardSection(
            title: "Top Artists",
            systemImage: "person.2.fill",
            totalCount: manager.topArtists.count,
            visibleCount: 6
        ) {
            TopArtistsView(
                artists: manager.topArtists,
                sortMetric: manager.sortMetric,
                hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                manager: manager
            )
            .navigationTitle("Top Artists")
        } content: {
            ForEach(Array(manager.topArtists.prefix(6).enumerated()), id: \.element.id) { index, artist in
                NavigationLink {
                    ArtistInfoView(artist: artist, manager: manager)
                } label: {
                    ArtistRow(artist: artist, sortMetric: manager.sortMetric, rank: index + 1)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct iPadDashboardMetric: Identifiable {
    let title: String
    let value: String
    let systemImage: String

    var id: String { title }
}

private struct iPadDashboardSummaryBar: View {
    let metrics: [iPadDashboardMetric]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            ForEach(metrics) { metric in
                HStack(spacing: 10) {
                    Image(systemName: metric.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.accentColor.opacity(0.10)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.value)
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(metric.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(minHeight: 56)
                .libraryGlassSurface(cornerRadius: 14, tintOpacity: 0.05)
            }
        }
    }
}

private struct iPadDashboardSection<Destination: View, Content: View>: View {
    let title: String
    let systemImage: String
    let totalCount: Int
    let visibleCount: Int
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Spacer(minLength: 8)

                if totalCount > visibleCount {
                    NavigationLink {
                        destination()
                    } label: {
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show all \(title.lowercased())")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .libraryGlassSurface(cornerRadius: 18, tintOpacity: 0.06)
    }
}

private struct iPadDashboardEmptyState: View {
    let hasLoadedInitialSnapshot: Bool

    var body: some View {
        VStack(spacing: 16) {
            EmptyLibraryArtworkCluster(systemImage: hasLoadedInitialSnapshot ? "music.note.slash" : "music.note.list")

            if hasLoadedInitialSnapshot {
                Text("No Plays Yet")
                    .font(.title3.weight(.semibold))
                Text("Play songs from your library to see your all-time rankings here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Loading your library…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .libraryGlassSurface(cornerRadius: 18, tintOpacity: 0.06)
    }
}
