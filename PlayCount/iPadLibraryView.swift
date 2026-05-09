import SwiftUI

struct iPadLibraryView: View {
    private enum LibraryTab: String, Hashable {
        case songs
        case albums
        case artists
        case recap
        case search
    }

    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab: LibraryTab = .songs
    @State private var presentedNowPlayingSong: TopSong?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Songs", systemImage: "music.note.list", value: LibraryTab.songs) {
                NavigationStack {
                    TopSongsView(
                        songs: manager.topSongs,
                        sortMetric: manager.sortMetric,
                        hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                        manager: manager
                    )
                    .navigationTitle("Top Songs")
                    .navigationBarTitleDisplayMode(.large)
                    .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                    .toolbar { toolbarContent }
                }
            }

            Tab("Albums", systemImage: "rectangle.stack", value: LibraryTab.albums) {
                NavigationStack {
                    TopAlbumsView(
                        albums: manager.topAlbums,
                        sortMetric: manager.sortMetric,
                        hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                        manager: manager
                    )
                    .navigationTitle("Top Albums")
                    .navigationBarTitleDisplayMode(.large)
                    .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                    .toolbar { toolbarContent }
                }
            }

            Tab("Artists", systemImage: "person.2.fill", value: LibraryTab.artists) {
                NavigationStack {
                    TopArtistsView(
                        artists: manager.topArtists,
                        sortMetric: manager.sortMetric,
                        hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                        manager: manager
                    )
                    .navigationTitle("Top Artists")
                    .navigationBarTitleDisplayMode(.large)
                    .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                    .toolbar { toolbarContent }
                }
            }

            Tab("Recap", systemImage: "calendar", value: LibraryTab.recap) {
                NavigationStack {
                    MonthlyRecapView(manager: manager)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: LibraryTab.search, role: .search) {
                NavigationStack {
                    LibrarySearchView(manager: manager)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                        .toolbar { toolbarContent }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
