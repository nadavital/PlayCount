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

        static func screenshotItemIndex(for argument: String) -> Int {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: argument),
                  arguments.indices.contains(index + 1),
                  let value = Int(arguments[index + 1]) else {
                return 0
            }
            return max(0, value)
            #else
            return 0
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
                                    PlayCountSheetDismissButton {
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
                LibrarySearchView(manager: manager)
                    .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
            }
        }
        .tabViewStyle(.tabBarOnly)
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
            let index = LibraryTab.screenshotItemIndex(for: "-PlayCountScreenshotArtistIndex")
            if manager.topArtists.indices.contains(index) {
                presentedScreenshotArtist = manager.topArtists[index]
            }
        }
        .task {
            guard LibraryTab.screenshotPresentsAlbumDetail else { return }
            try? await Task.sleep(for: .milliseconds(350))
            let index = LibraryTab.screenshotItemIndex(for: "-PlayCountScreenshotAlbumIndex")
            if manager.topAlbums.indices.contains(index) {
                presentedScreenshotAlbum = manager.topAlbums[index]
            }
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
        .frame(height: 32)
        .accessibilityHint("Switches the library ranking")
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


/// Use available width for rankings while keeping large text in one readable column.
struct AdaptiveLibraryRows<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: Content
    @State private var divisionColumns: VerticalDivisionColumns?

    private var columns: [GridItem] {
        if let divisionColumns {
            return divisionColumns.gridItems
        }
        return [GridItem(.adaptive(minimum: 340), spacing: 12)]
    }

    var body: some View {
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: columns, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity)
            .modifier(VerticalDivisionObserver(columns: $divisionColumns))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        } else {
            content
        }
    }
}

struct VerticalDivisionColumns: Equatable {
    let leading: CGFloat
    let trailing: CGFloat
    let spacing: CGFloat

    var gridItems: [GridItem] {
        [
            GridItem(.fixed(leading), spacing: spacing, alignment: .top),
            GridItem(.fixed(trailing), spacing: 0, alignment: .top)
        ]
    }
}

struct VerticalDivisionObserver: ViewModifier {
    @Binding var columns: VerticalDivisionColumns?

    @ViewBuilder
    func body(content: Content) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: VerticalDivisionColumns?.self) { geometry in
                // Keep each card on one side of an active book fold. Horizontal
                // divisions retain the grid's continuous vertical scrolling.
                guard let division = geometry.reservedRegions(kind: .division).first(where: {
                    $0.isActive && $0.frame.height > $0.frame.width &&
                    $0.frame.minX > 0 && $0.frame.maxX < geometry.size.width
                }) else { return nil }
                let leading = division.frame.minX - division.margins.leading
                let trailing = geometry.size.width - division.frame.maxX - division.margins.trailing
                guard leading > 0, trailing > 0 else { return nil }
                return VerticalDivisionColumns(
                    leading: leading,
                    trailing: trailing,
                    spacing: geometry.size.width - leading - trailing
                )
            } action: { columns = $0 }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct AdaptiveLibraryRowSurface: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            content
                .buttonStyle(.plain)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: .rect(cornerRadius: 18))
        } else {
            content
        }
    }
}
