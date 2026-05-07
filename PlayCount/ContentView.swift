import SwiftUI
import MediaPlayer

struct ContentView: View {
    @StateObject private var libraryManager: MediaLibraryManager
    @Environment(\.scenePhase) private var scenePhase

    init(libraryManager: MediaLibraryManager = .shared) {
        _libraryManager = StateObject(wrappedValue: libraryManager)
    }

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
            if libraryManager.authorizationStatus == .authorized {
                libraryManager.refreshForRecapSequence(reason: .appLaunch)
            } else {
                libraryManager.requestAuthorizationIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            if libraryManager.authorizationStatus == .authorized {
                libraryManager.refreshForRecapSequence(reason: .foreground)
            } else {
                libraryManager.requestAuthorizationIfNeeded()
            }
        }
    }
}

private struct AuthorizedLibraryView: View {
    private enum LibraryTab: Hashable {
        case songs
        case albums
        case artists
        case recap
        case search

        static var screenshotInitialTab: Self {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-PlayCountScreenshotTab"),
               arguments.indices.contains(index + 1) {
                switch arguments[index + 1].lowercased() {
                case "albums":
                    return .albums
                case "artists":
                    return .artists
                case "recap":
                    return .recap
                case "search":
                    return .search
                default:
                    return .songs
                }
            }
            #endif

            return .songs
        }

        static var screenshotPresentsNowPlaying: Bool {
            #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotNowPlayingDetail")
            #else
            false
            #endif
        }

        static var screenshotPresentsArtistDetail: Bool {
            #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotArtistDetail")
            #else
            false
            #endif
        }
    }

    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: LibraryTab = .screenshotInitialTab
    @State private var presentedNowPlayingSong: TopSong?
    @State private var presentedScreenshotArtist: TopArtist?

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
                    TopAlbumsView(albums: manager.topAlbums, sortMetric: manager.sortMetric, hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot, manager: manager)
                        .navigationTitle("Top Albums")
                        .navigationBarTitleDisplayMode(.large)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                        .toolbar { toolbarContent }
                }
            }

            Tab("Artists", systemImage: "person.2.fill", value: LibraryTab.artists) {
                NavigationStack {
                    TopArtistsView(artists: manager.topArtists, sortMetric: manager.sortMetric, hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot, manager: manager)
                        .navigationTitle("Top Artists")
                        .navigationBarTitleDisplayMode(.large)
                        .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                        .toolbar { toolbarContent }
                }
            }

            Tab("Recap", systemImage: "calendar", value: LibraryTab.recap) {
                NavigationStack {
                    MonthlyRecapView(manager: manager)
                        .toolbar(.hidden, for: .navigationBar)
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
        .sheet(item: $presentedScreenshotArtist) { artist in
            NavigationStack {
                ArtistInfoView(artist: artist, manager: manager)
            }
        }
        .task {
            guard LibraryTab.screenshotPresentsNowPlaying else { return }
            try? await Task.sleep(for: .milliseconds(350))
            if let song = manager.nowPlayingState?.song {
                presentedNowPlayingSong = song
            }
        }
        .task {
            guard LibraryTab.screenshotPresentsArtistDetail else { return }
            try? await Task.sleep(for: .milliseconds(350))
            presentedScreenshotArtist = manager.topArtists.first
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
