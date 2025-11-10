import SwiftUI
import MediaPlayer

struct ContentView: View {
    @StateObject private var libraryManager = MediaLibraryManager()

    var body: some View {
        Group {
            switch libraryManager.authorizationStatus {
            case .authorized:
                AuthorizedLibraryView(manager: libraryManager)
            case .notDetermined:
                RequestingAccessView()
            case .denied, .restricted:
                AccessDeniedView(onRetry: libraryManager.requestAuthorizationIfNeeded)
            @unknown default:
                AccessDeniedView(onRetry: libraryManager.requestAuthorizationIfNeeded)
            }
        }
        .task {
            libraryManager.requestAuthorizationIfNeeded()
        }
    }
}

private struct AuthorizedLibraryView: View {
    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.colorScheme) var colorScheme
    @State private var presentedNowPlayingSong: TopSong?

    var body: some View {
        TabView {
            Tab("Songs", systemImage: "music.note.list") {
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

            Tab("Albums", systemImage: "rectangle.stack") {
                NavigationStack {
                    TopAlbumsView(albums: manager.topAlbums, sortMetric: manager.sortMetric, hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot, manager: manager)
                        .navigationTitle("Top Albums")
                        .navigationBarTitleDisplayMode(.large)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                        .toolbar { toolbarContent }
                }
            }

            Tab("Artists", systemImage: "person.2.fill") {
                NavigationStack {
                    TopArtistsView(artists: manager.topArtists, sortMetric: manager.sortMetric, hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot, manager: manager)
                        .navigationTitle("Top Artists")
                        .navigationBarTitleDisplayMode(.large)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                        .toolbar { toolbarContent }
                }
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    LibrarySearchView(manager: manager)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                        .toolbar { toolbarContent }
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory{

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
        .onChange(of: manager.nowPlayingState) { state in
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
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup() {
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

private struct RequestingAccessView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Requesting access to your media library…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AccessDeniedView: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Media Library Access Needed")
                .font(.title3).bold()

            Text("Grant access in Settings to see your top songs, albums, and artists.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Go to Settings > Privacy & Media & Apple Music, enable access for PlayCount, then come back here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Check Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    ContentView()
}
