import SwiftUI

struct LibrarySearchView: View {
    @ObservedObject var manager: MediaLibraryManager
    @ObservedObject private var libraryUpdates: MediaLibraryManager.DetailPresentationUpdates
    @State private var searchText: String = ""
    @State private var settledSearchText: String = ""
    @State private var selectedDomain: SearchDomain = .all
    @State private var selectedResult: SearchResult?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if DEBUG
    @State private var hasAppliedScreenshotSelection = false
    #endif

    private enum SearchResult: Hashable {
        case song(UInt64)
        case album(UInt64)
        case artist(UInt64, String)
    }

    private enum SearchDomain: String, CaseIterable, Identifiable {
        case all
        case songs
        case albums
        case artists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .songs: return "Songs"
            case .albums: return "Albums"
            case .artists: return "Artists"
            }
        }

        var searchPrompt: String {
            switch self {
            case .all: return "Search your library"
            case .songs: return "Search songs"
            case .albums: return "Search albums"
            case .artists: return "Search artists"
            }
        }
    }

    init(manager: MediaLibraryManager) {
        self.manager = manager
        _libraryUpdates = ObservedObject(wrappedValue: manager.detailPresentationUpdates)

        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-PlayCountScreenshotSearchQuery"),
           arguments.indices.contains(index + 1) {
            _searchText = State(initialValue: arguments[index + 1])
            _settledSearchText = State(initialValue: arguments[index + 1])
        }
        if let index = arguments.firstIndex(of: "-PlayCountScreenshotSearchDomain"),
           arguments.indices.contains(index + 1),
           let domain = SearchDomain(rawValue: arguments[index + 1].lowercased()) {
            _selectedDomain = State(initialValue: domain)
        }
        #endif
    }

    var body: some View {
        let _ = libraryUpdates.revision
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $preferredCompactColumn) {
            resultsList
                .environment(\.horizontalSizeClass, .compact)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(selectedDomain.searchPrompt))
                .searchScopes($selectedDomain) {
                    ForEach(SearchDomain.allCases) { domain in
                        Text(domain.title).tag(domain)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        LibraryMetricPicker(selection: $manager.sortMetric)
                    }
                }
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 480)
        } detail: {
            NavigationStack {
                resultDetail
                    .navigationBarBackButtonHidden(horizontalSizeClass == .compact)
                    .toolbar {
                        if horizontalSizeClass == .compact {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Search", systemImage: "chevron.backward") {
                                    preferredCompactColumn = .sidebar
                                }
                                .accessibilityLabel("Back to Search")
                                .accessibilityIdentifier("search-back")
                            }
                        }
                    }
            }
            .id(selectedResult)
        }
        .navigationSplitViewStyle(.balanced)
            .task {
                #if DEBUG
                if !hasAppliedScreenshotSelection,
                   ProcessInfo.processInfo.arguments.contains("-PlayCountScreenshotSearchSelection"),
                   let song = manager.topSongs.first {
                    hasAppliedScreenshotSelection = true
                    select(.song(song.id))
                }
                #endif
            }
            .task(id: searchText) {
                let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    try? await Task.sleep(for: .milliseconds(180))
                }
                guard !Task.isCancelled else { return }
                settledSearchText = trimmed
            }
    }

    private var library: MediaLibraryManager.SearchPresentation { manager.searchPresentation }

    @ViewBuilder
    private var resultDetail: some View {
        switch selectedResult {
        case .song(let id):
            if let song = library.songs.first(where: { id != 0 && $0.id == id }) {
                SongInfoView(song: song, manager: manager)
            } else { unavailableResult }
        case .album(let id):
            if let album = library.albums.first(where: { id != 0 && $0.id == id }) {
                AlbumInfoView(album: album, manager: manager)
            } else { unavailableResult }
        case .artist(let id, let name):
            if let artist = library.artists.first(where: { id != 0 && $0.id == id }) ?? library.artists.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                ArtistInfoView(artist: artist, manager: manager)
            } else { unavailableResult }
        case nil:
            ContentUnavailableView("Explore Your Library", systemImage: "music.note.magnifyingglass", description: Text("Select a song, album, or artist to see its listening history."))
        }
    }

    private var unavailableResult: some View {
        ContentUnavailableView("No Longer in Your Library", systemImage: "music.note", description: Text("Select another search result."))
    }

    private var resultsList: some View {
        List {
            if manager.isLoading && !manager.hasLoadedInitialSnapshot {
                LoadingListSection(title: manager.loadingStage.message ?? "Indexing your media library…")
            } else if trimmedQuery.isEmpty {
                suggestionsContent
            } else {
                resultsContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.hasLoadedInitialSnapshot)
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .playCountSoftTopScrollEdge()
        .navigationTitle("Search")
        .playCountPrimaryTitleDisplayMode()
    }

    private var trimmedQuery: String {
        settledSearchText
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch selectedDomain {
        case .all:
            allResults
        case .songs:
            songsResults
        case .albums:
            albumsResults
        case .artists:
            artistsResults
        }
    }

    private var filteredSongs: [TopSong] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return boundedMatches(in: library.songs) {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query) ||
                $0.albumTitle.localizedCaseInsensitiveContains(query)
            } areInIncreasingOrder: { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    @ViewBuilder
    private var suggestionsContent: some View {
        if library.songs.isEmpty && library.topAlbums.isEmpty && library.topArtists.isEmpty {
            EmptyLibrarySection(
                systemImage: "magnifyingglass",
                title: "Search Your Library",
                message: "Find songs, albums, and artists from one place."
            )
        } else {
            if selectedDomain == .all {
                Section("System Integration") {
                    NavigationLink {
                        SystemIntegrationView(manager: manager)
                    } label: {
                        Label("Siri & Shortcuts", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
            }

            if selectedDomain == .all || selectedDomain == .songs {
                Section("Recently Played") {
                    if library.recentlyPlayedSongs.isEmpty {
                        Label("No recent library plays yet", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    } else {
                        AdaptiveLibraryRows {
                            ForEach(library.recentlyPlayedSongs.prefix(5)) { song in
                                recentSongLink(song)
                                    .modifier(AdaptiveLibraryRowSurface())
                            }
                        }
                    }
                }
            }

            if selectedDomain == .all || selectedDomain == .albums {
                Section("Top Albums") {
                    AdaptiveLibraryRows {
                        ForEach(library.topAlbums.prefix(3)) { album in
                            albumLink(album)
                                .modifier(AdaptiveLibraryRowSurface())
                        }
                    }
                }
            }

            if selectedDomain == .all || selectedDomain == .artists {
                Section("Top Artists") {
                    AdaptiveLibraryRows {
                        ForEach(library.topArtists.prefix(3)) { artist in
                            artistLink(artist)
                                .modifier(AdaptiveLibraryRowSurface())
                        }
                    }
                }
            }

        }
    }

    @ViewBuilder
    private var allResults: some View {
        let songs = filteredSongs
        let albums = filteredAlbums
        let artists = filteredArtists

        if songs.isEmpty && albums.isEmpty && artists.isEmpty {
            EmptyLibrarySection(
                systemImage: "magnifyingglass",
                title: "No Matches",
                message: "Try another title, album, or artist."
            )
        } else {
            if !songs.isEmpty {
                Section("Songs") {
                    AdaptiveLibraryRows {
                        ForEach(songs.prefix(8)) { song in
                            songLink(song)
                                .modifier(AdaptiveLibraryRowSurface())
                        }
                    }
                }
            }

            if !albums.isEmpty {
                Section("Albums") {
                    AdaptiveLibraryRows {
                        ForEach(albums.prefix(8)) { album in
                            albumLink(album)
                                .modifier(AdaptiveLibraryRowSurface())
                        }
                    }
                }
            }

            if !artists.isEmpty {
                Section("Artists") {
                    AdaptiveLibraryRows {
                        ForEach(artists.prefix(8)) { artist in
                            artistLink(artist)
                                .modifier(AdaptiveLibraryRowSurface())
                        }
                    }
                }
            }
        }
    }

    private var filteredAlbums: [TopAlbum] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return boundedMatches(in: library.albums) {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query)
            } areInIncreasingOrder: { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var filteredArtists: [TopArtist] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return boundedMatches(in: library.artists) {
                $0.name.localizedCaseInsensitiveContains(query)
            } areInIncreasingOrder: { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func boundedMatches<Element>(
        in elements: [Element],
        limit: Int = 50,
        matches: (Element) -> Bool,
        areInIncreasingOrder: (Element, Element) -> Bool
    ) -> [Element] {
        var result: [Element] = []
        result.reserveCapacity(limit)

        for element in elements where matches(element) {
            let insertionIndex = result.firstIndex {
                areInIncreasingOrder(element, $0)
            } ?? result.endIndex
            result.insert(element, at: insertionIndex)
            if result.count > limit {
                result.removeLast()
            }
        }

        return result
    }

    @ViewBuilder
    private var songsResults: some View {
        let songs = filteredSongs
        if songs.isEmpty {
            EmptyLibrarySection(
                systemImage: "music.note",
                title: "No Matching Songs",
                message: "Try a different title or artist."
            )
        } else {
            AdaptiveLibraryRows {
                ForEach(songs) { song in
                    songLink(song)
                        .modifier(AdaptiveLibraryRowSurface())
                }
            }
        }
    }

    @ViewBuilder
    private var albumsResults: some View {
        let albums = filteredAlbums
        if albums.isEmpty {
            EmptyLibrarySection(
                systemImage: "rectangle.stack.badge.slash",
                title: "No Matching Albums",
                message: "We couldn't find albums that match your search."
            )
        } else {
            AdaptiveLibraryRows {
                ForEach(albums) { album in
                    albumLink(album)
                        .modifier(AdaptiveLibraryRowSurface())
                }
            }
        }
    }

    @ViewBuilder
    private var artistsResults: some View {
        let artists = filteredArtists
        if artists.isEmpty {
            EmptyLibrarySection(
                systemImage: "person.crop.circle.badge.questionmark",
                title: "No Matching Artists",
                message: "Adjust your spelling or search for another artist."
            )
        } else {
            AdaptiveLibraryRows {
                ForEach(artists) { artist in
                    artistLink(artist)
                        .modifier(AdaptiveLibraryRowSurface())
                }
            }
        }
    }

    private func select(_ result: SearchResult) {
        selectedResult = result
        preferredCompactColumn = .detail
    }

    private func songLink(_ song: TopSong) -> some View {
        Button {
            select(.song(song.id))
        } label: {
            SongRow(song: song, sortMetric: manager.sortMetric)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedResult == .song(song.id) ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(selectedResult == .song(song.id) ? .isSelected : [])
        .playCountSongEntityIdentifier(song)
    }

    private func recentSongLink(_ song: TopSong) -> some View {
        Button {
            select(.song(song.id))
        } label: {
            HStack(spacing: 12) {
                ArtworkView(
                    artwork: song.artwork,
                    size: CGSize(width: 48, height: 48),
                    cornerRadius: 9
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let lastPlayedDate = song.lastPlayedDate {
                    Text(lastPlayedDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedResult == .song(song.id) ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(selectedResult == .song(song.id) ? .isSelected : [])
        .playCountSongEntityIdentifier(song)
    }

    private func albumLink(_ album: TopAlbum) -> some View {
        Button {
            select(.album(album.id))
        } label: {
            AlbumRow(album: album, sortMetric: manager.sortMetric)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedResult == .album(album.id) ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(selectedResult == .album(album.id) ? .isSelected : [])
        .playCountAlbumEntityIdentifier(album)
    }

    private func artistLink(_ artist: TopArtist) -> some View {
        Button {
            select(.artist(artist.id, artist.name))
        } label: {
            ArtistRow(artist: artist, sortMetric: manager.sortMetric)
        }
        .buttonStyle(.plain)
        .listRowBackground(selectedResult == .artist(artist.id, artist.name) ? Color.accentColor.opacity(0.12) : nil)
        .accessibilityAddTraits(selectedResult == .artist(artist.id, artist.name) ? .isSelected : [])
        .playCountArtistEntityIdentifier(artist)
    }
}

#Preview {
    LibrarySearchView(manager: MediaLibraryManager())
}
