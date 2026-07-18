import SwiftUI

struct LibrarySearchView: View {
    @ObservedObject var manager: MediaLibraryManager
    @State private var searchText: String = ""
    @State private var settledSearchText: String = ""
    @State private var selectedDomain: SearchDomain = .all

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
        .navigationTitle("Search")
        .playCountPrimaryTitleDisplayMode()
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(selectedDomain.searchPrompt))
        .searchScopes($selectedDomain) {
            ForEach(SearchDomain.allCases) { domain in
                Text(domain.title).tag(domain)
            }
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
        return boundedMatches(in: manager.librarySongs) {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query) ||
                $0.albumTitle.localizedCaseInsensitiveContains(query)
            } areInIncreasingOrder: { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    @ViewBuilder
    private var suggestionsContent: some View {
        if manager.topSongs.isEmpty && manager.topAlbums.isEmpty && manager.topArtists.isEmpty {
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
                Section("Top Songs") {
                    ForEach(manager.topSongs.prefix(3)) { song in
                        songLink(song)
                    }
                }
            }

            if selectedDomain == .all || selectedDomain == .albums {
                Section("Top Albums") {
                    ForEach(manager.topAlbums.prefix(3)) { album in
                        albumLink(album)
                    }
                }
            }

            if selectedDomain == .all || selectedDomain == .artists {
                Section("Top Artists") {
                    ForEach(manager.topArtists.prefix(3)) { artist in
                        artistLink(artist)
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
                    ForEach(songs.prefix(8)) { song in
                        songLink(song)
                    }
                }
            }

            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums.prefix(8)) { album in
                        albumLink(album)
                    }
                }
            }

            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists.prefix(8)) { artist in
                        artistLink(artist)
                    }
                }
            }
        }
    }

    private var filteredAlbums: [TopAlbum] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return boundedMatches(in: manager.libraryAlbums) {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query)
            } areInIncreasingOrder: { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var filteredArtists: [TopArtist] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return boundedMatches(in: manager.libraryArtists) {
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
            ForEach(songs) { song in
                NavigationLink {
                    SongInfoView(song: song, manager: manager)
                } label: {
                    SongRow(song: song, sortMetric: manager.sortMetric)
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
            ForEach(albums) { album in
                NavigationLink {
                    AlbumInfoView(album: album, manager: manager)
                } label: {
                    AlbumRow(album: album, sortMetric: manager.sortMetric)
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
            ForEach(artists) { artist in
                NavigationLink {
                    ArtistInfoView(artist: artist, manager: manager)
                } label: {
                    ArtistRow(artist: artist, sortMetric: manager.sortMetric)
                }
            }
        }
    }

    private func songLink(_ song: TopSong) -> some View {
        NavigationLink {
            SongInfoView(song: song, manager: manager)
        } label: {
            SongRow(song: song, sortMetric: manager.sortMetric)
        }
    }

    private func albumLink(_ album: TopAlbum) -> some View {
        NavigationLink {
            AlbumInfoView(album: album, manager: manager)
        } label: {
            AlbumRow(album: album, sortMetric: manager.sortMetric)
        }
    }

    private func artistLink(_ artist: TopArtist) -> some View {
        NavigationLink {
            ArtistInfoView(artist: artist, manager: manager)
        } label: {
            ArtistRow(artist: artist, sortMetric: manager.sortMetric)
        }
    }
}

#Preview {
    NavigationStack {
        LibrarySearchView(manager: MediaLibraryManager())
    }
}
