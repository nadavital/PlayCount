import SwiftUI

struct iPadLibraryView: View {
    private enum LibrarySection: String, CaseIterable, Identifiable {
        case overview
        case songs
        case albums
        case artists
        case recap
        case search

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "Overview"
            case .songs: "Songs"
            case .albums: "Albums"
            case .artists: "Artists"
            case .recap: "Recap"
            case .search: "Search"
            }
        }

        var systemImage: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .songs: "music.note.list"
            case .albums: "rectangle.stack"
            case .artists: "person.2.fill"
            case .recap: "calendar"
            case .search: "magnifyingglass"
            }
        }
    }

    @ObservedObject var manager: MediaLibraryManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: LibrarySection? = .overview
    @State private var presentedNowPlayingSong: TopSong?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Library") {
                    ForEach(LibrarySection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
            }
            .navigationTitle("PlayCount")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                sectionView
                    .navigationTitle((selectedSection ?? .overview).title)
                    .navigationBarTitleDisplayMode(.large)
                    .libraryStatusOverlay(isLoading: manager.isLoading, message: manager.errorMessage)
                    .toolbar { toolbarContent }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom) {
            iPadNowPlayingDock(manager: manager) { state in
                if let song = state.song {
                    presentedNowPlayingSong = song
                }
            }
            .environment(\.colorScheme, colorScheme)
            .padding(.horizontal, 28)
            .padding(.bottom, 10)
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
            selectedSection = .recap
        }
    }

    @ViewBuilder
    private var sectionView: some View {
        switch selectedSection ?? .overview {
        case .overview:
            iPadOverviewView(manager: manager)
        case .songs:
            TopSongsView(
                songs: manager.topSongs,
                sortMetric: manager.sortMetric,
                hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                manager: manager
            )
        case .albums:
            TopAlbumsView(
                albums: manager.topAlbums,
                sortMetric: manager.sortMetric,
                hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                manager: manager
            )
        case .artists:
            TopArtistsView(
                artists: manager.topArtists,
                sortMetric: manager.sortMetric,
                hasLoadedInitialSnapshot: manager.hasLoadedInitialSnapshot,
                manager: manager
            )
        case .recap:
            MonthlyRecapView(manager: manager)
        case .search:
            LibrarySearchView(manager: manager)
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

private struct iPadOverviewView: View {
    @ObservedObject var manager: MediaLibraryManager

    private var topSong: TopSong? { manager.topSongs.first }
    private var topAlbum: TopAlbum? { manager.topAlbums.first }
    private var topArtist: TopArtist? { manager.topArtists.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                iPadHeroPanel(manager: manager, song: topSong, album: topAlbum, artist: topArtist)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 280), spacing: 18),
                        GridItem(.flexible(minimum: 280), spacing: 18),
                        GridItem(.flexible(minimum: 280), spacing: 18)
                    ],
                    spacing: 18
                ) {
                    iPadTopSongCard(song: topSong, manager: manager)
                    iPadTopAlbumCard(album: topAlbum, manager: manager)
                    iPadTopArtistCard(artist: topArtist, manager: manager)
                }

                iPadLeaderboardShelf(manager: manager)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .background(iPadLibraryBackground())
    }
}

private struct iPadHeroPanel: View {
    @ObservedObject var manager: MediaLibraryManager
    let song: TopSong?
    let album: TopAlbum?
    let artist: TopArtist?

    private var totalPlays: Int {
        manager.topSongs.reduce(0) { $0 + $1.playCount }
    }

    private var totalListeningTime: TimeInterval {
        manager.topSongs.reduce(0) { $0 + $1.totalPlayDuration }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.thinMaterial)

                if let song {
                    ArtworkView(
                        artwork: song.artwork,
                        size: CGSize(width: 224, height: 224),
                        cornerRadius: 28
                    )
                    .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 18)
                } else {
                    EmptyLibraryArtworkCluster(systemImage: "music.note.list")
                }
            }
            .frame(width: 280, height: 280)
            .libraryGlassSurface(cornerRadius: 36, tintOpacity: 0.12)

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Library, Wide Open")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .lineLimit(2)
                    Text(heroSubtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    iPadStatPill(title: "Songs", value: "\(manager.topSongs.count)", systemImage: "music.note")
                    iPadStatPill(title: "Plays", value: totalPlays.detailFormatted, systemImage: "number")
                    iPadStatPill(title: "Time", value: totalListeningTime.formattedListeningMinutes, systemImage: "clock")
                }

                if let album, let artist {
                    HStack(spacing: 10) {
                        Label(album.title, systemImage: "rectangle.stack.fill")
                        Label(artist.name, systemImage: "person.fill")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private var heroSubtitle: String {
        guard let song else {
            return "Start playing music and PlayCount will turn the full iPad canvas into a living map of what you love."
        }
        return "\(song.title) by \(song.artist) is leading your library right now."
    }
}

private struct iPadTopSongCard: View {
    let song: TopSong?
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        iPadFeatureCard(title: "Top Song", systemImage: "music.note") {
            if let song {
                NavigationLink {
                    SongInfoView(song: song, manager: manager)
                } label: {
                    iPadCardMediaContent(
                        title: song.title,
                        subtitle: song.artist,
                        metric: "\(song.playCount.detailFormatted) plays",
                        artwork: {
                            ArtworkView(artwork: song.artwork, size: CGSize(width: 86, height: 86), cornerRadius: 18)
                        }
                    )
                }
                .buttonStyle(.plain)
            } else {
                iPadEmptyCardText()
            }
        }
    }
}

private struct iPadTopAlbumCard: View {
    let album: TopAlbum?
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        iPadFeatureCard(title: "Top Album", systemImage: "rectangle.stack") {
            if let album {
                NavigationLink {
                    AlbumInfoView(album: album, manager: manager)
                } label: {
                    iPadCardMediaContent(
                        title: album.title,
                        subtitle: album.artist,
                        metric: "\(album.playCount.detailFormatted) plays",
                        artwork: {
                            ArtworkView(artwork: album.artwork, size: CGSize(width: 86, height: 86), cornerRadius: 18)
                        }
                    )
                }
                .buttonStyle(.plain)
            } else {
                iPadEmptyCardText()
            }
        }
    }
}

private struct iPadTopArtistCard: View {
    let artist: TopArtist?
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        iPadFeatureCard(title: "Top Artist", systemImage: "person.2.fill") {
            if let artist {
                NavigationLink {
                    ArtistInfoView(artist: artist, manager: manager)
                } label: {
                    iPadCardMediaContent(
                        title: artist.name,
                        subtitle: "Artist",
                        metric: "\(artist.playCount.detailFormatted) plays",
                        artwork: {
                            ArtistArtworkView(artwork: artist.artwork, name: artist.name, diameter: 86)
                        }
                    )
                }
                .buttonStyle(.plain)
            } else {
                iPadEmptyCardText()
            }
        }
    }
}

private struct iPadFeatureCard<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

private struct iPadCardMediaContent<Artwork: View>: View {
    let title: String
    let subtitle: String
    let metric: String
    private let artwork: Artwork

    init(
        title: String,
        subtitle: String,
        metric: String,
        @ViewBuilder artwork: () -> Artwork
    ) {
        self.title = title
        self.subtitle = subtitle
        self.metric = metric
        self.artwork = artwork()
    }

    var body: some View {
        HStack(spacing: 16) {
            artwork
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                MetricBadge(text: metric)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct iPadEmptyCardText: View {
    var body: some View {
        Text("Your rankings will appear here after PlayCount scans the library.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct iPadStatPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
    }
}

private struct iPadLeaderboardShelf: View {
    @ObservedObject var manager: MediaLibraryManager

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: 18),
            GridItem(.flexible(minimum: 320), spacing: 18)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rankings at a Glance")
                .font(.title2.weight(.bold))

            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                iPadRankColumn(title: "Songs", systemImage: "music.note.list") {
                    ForEach(Array(manager.topSongs.prefix(5).enumerated()), id: \.element.id) { index, song in
                        NavigationLink {
                            SongInfoView(song: song, manager: manager)
                        } label: {
                            SongRow(song: song, sortMetric: manager.sortMetric, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                    }
                }

                iPadRankColumn(title: "Artists", systemImage: "person.2.fill") {
                    ForEach(Array(manager.topArtists.prefix(5).enumerated()), id: \.element.id) { index, artist in
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
    }
}

private struct iPadRankColumn<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                content
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

private struct iPadNowPlayingDock: View {
    @ObservedObject var manager: MediaLibraryManager
    var onTap: (MediaLibraryManager.NowPlayingState) -> Void

    var body: some View {
        if let state = manager.nowPlayingState {
            HStack(spacing: 14) {
                ArtworkView(artwork: state.artwork, size: CGSize(width: 48, height: 48), cornerRadius: 12)
                    .id(state.song?.id)

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(state.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 16)

                Button(action: manager.togglePlayback) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)

                Button(action: manager.skipForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: 760)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08))
            }
            .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
            .contentShape(Capsule())
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Opens the current song details"))
            .onTapGesture {
                onTap(state)
            }
        }
    }
}

private struct iPadLibraryBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground),
                Color.accentColor.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
