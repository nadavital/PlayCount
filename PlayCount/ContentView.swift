import SwiftUI
import MediaPlayer
import UIKit

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
        case library
        case recap
        case search

        static var screenshotInitialTab: Self {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-PlayCountScreenshotTab"),
               arguments.indices.contains(index + 1) {
                switch arguments[index + 1].lowercased() {
                case "recap":
                    return .recap
                case "search":
                    return .search
                default:
                    return .library
                }
            }
            #endif

            return .library
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

        static var screenshotPresentsAlbumDetail: Bool {
            #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotAlbumDetail")
            #else
            false
            #endif
        }

        static var isScreenshotModeEnabled: Bool {
            #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotMode") ||
                ProcessInfo.processInfo.environment["PLAYCOUNT_SCREENSHOT_MODE"] == "1"
            #else
            false
            #endif
        }
    }

    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: LibraryTab = .screenshotInitialTab
    @State private var presentedNowPlayingSong: TopSong?
    @State private var detailPresentationOwner = UUID()
    @State private var presentedScreenshotArtist: TopArtist?
    @State private var presentedScreenshotAlbum: TopAlbum?

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadBody
        } else {
            iPhoneBody
        }
    }

    private var iPadBody: some View {
        iPadLibraryView(manager: manager)
            .fullScreenCover(item: $presentedScreenshotArtist) { artist in
                NavigationStack {
                    ArtistInfoView(artist: artist, manager: manager, reservesBottomAccessorySpace: false)
                        .toolbar {
                            if !LibraryTab.isScreenshotModeEnabled {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") {
                                        presentedScreenshotArtist = nil
                                    }
                                }
                            }
                        }
                        .toolbar(LibraryTab.isScreenshotModeEnabled ? .hidden : .visible, for: .navigationBar)
                }
            }
            .task {
                guard LibraryTab.screenshotPresentsArtistDetail else { return }
                try? await Task.sleep(for: .milliseconds(350))
                presentedScreenshotArtist = manager.topArtists.first
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMonthlyRecap)) { _ in
                manager.refreshForRecapSequence(reason: .notificationOpen)
            }
    }

    private var iPhoneBody: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "music.note.house.fill", value: LibraryTab.library) {
                NavigationStack {
                    PhoneLibraryView(manager: manager)
                        .navigationTitle("Library")
                        .playCountPrimaryTitleDisplayMode()
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
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(
            NowPlayingAccessoryModifier(
                manager: manager,
                colorScheme: colorScheme,
                presentedSong: $presentedNowPlayingSong
            )
        )
        .sheet(item: $presentedNowPlayingSong) { song in
            NavigationStack {
                SongInfoView(song: song, manager: manager)
            }
            .presentationContentInteraction(.scrolls)
        }
        .onChange(of: presentedNowPlayingSong?.id, initial: true) { _, songID in
            manager.setDetailPresentationActive(songID != nil, owner: detailPresentationOwner)
        }
        .onDisappear {
            manager.setDetailPresentationActive(false, owner: detailPresentationOwner)
        }
        .sheet(item: $presentedScreenshotArtist) { artist in
            NavigationStack {
                ArtistInfoView(artist: artist, manager: manager)
            }
        }
        .sheet(item: $presentedScreenshotAlbum) { album in
            NavigationStack {
                AlbumInfoView(album: album, manager: manager)
            }
        }
        .task {
            if PlayCountNavigationRequestStore.consumeLatestRecapRequest() {
                selectedTab = .recap
            }
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
        .task {
            guard LibraryTab.screenshotPresentsAlbumDetail else { return }
            try? await Task.sleep(for: .milliseconds(350))
            presentedScreenshotAlbum = manager.topAlbums.first
        }
        .onChange(of: manager.nowPlayingState) { _, state in
            guard let state else {
                presentedNowPlayingSong = nil
                return
            }

            if let song = state.song,
               let presentedNowPlayingSong,
               presentedNowPlayingSong.id == song.id {
                if !presentedNowPlayingSong.isDetailEquivalent(to: song) {
                    self.presentedNowPlayingSong = song
                }
            } else if presentedNowPlayingSong != nil {
                presentedNowPlayingSong = state.song
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMonthlyRecap)) { _ in
            _ = PlayCountNavigationRequestStore.consumeLatestRecapRequest()
            selectedTab = .recap
            manager.refreshForRecapSequence(reason: .notificationOpen)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup() {
            sortPicker
        }
    }

    private var sortPicker: some View {
        LibraryMetricPicker(selection: $manager.sortMetric)
    }

}

private struct PhoneLibraryView: View {
    @ObservedObject var manager: MediaLibraryManager
    @State private var selection: LibraryCategory = Self.initialCategory

    private static var initialCategory: LibraryCategory {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-PlayCountScreenshotTab"),
           arguments.indices.contains(index + 1) {
            switch arguments[index + 1].lowercased() {
            case "albums": return .albums
            case "artists": return .artists
            default: return .songs
            }
        }
        #endif
        return .songs
    }

    var body: some View {
        Group {
            switch selection {
            case .songs:
                TopSongsView(
                    songs: manager.topSongs,
                    sortMetric: manager.sortMetric,
                    hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                    manager: manager,
                    categorySelection: $selection
                )
            case .albums:
                TopAlbumsView(
                    albums: manager.topAlbums,
                    sortMetric: manager.sortMetric,
                    hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                    manager: manager,
                    categorySelection: $selection
                )
            case .artists:
                TopArtistsView(
                    artists: manager.topArtists,
                    sortMetric: manager.sortMetric,
                    hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                    manager: manager,
                    categorySelection: $selection
                )
            }
        }
    }
}

enum LibraryCategory: String, CaseIterable, Identifiable {
    case songs = "Songs"
    case albums = "Albums"
    case artists = "Artists"

    var id: Self { self }
}

struct LibraryCategoryPicker: View {
    @Binding var selection: LibraryCategory

    var body: some View {
        Picker("Library category", selection: $selection) {
            ForEach(LibraryCategory.allCases) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
    }
}

private struct NowPlayingAccessoryModifier: ViewModifier {
    @ObservedObject var manager: MediaLibraryManager
    let colorScheme: ColorScheme
    @Binding var presentedSong: TopSong?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: manager.nowPlayingState != nil) {
                accessory
            }
        } else {
            content.tabViewBottomAccessory {
                if manager.nowPlayingState != nil {
                    accessory
                }
            }
        }
    }

    private var accessory: some View {
        NowPlayingBarView(manager: manager) { state in
            if let song = state.song {
                presentedSong = song
            }
        }
        .environment(\.colorScheme, colorScheme)
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
