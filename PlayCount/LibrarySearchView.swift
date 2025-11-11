import SwiftUI

struct LibrarySearchView: View {
    @ObservedObject var manager: MediaLibraryManager
    @State private var searchText: String = ""
    @State private var selectedDomain: SearchDomain = .songs

    private enum SearchDomain: String, CaseIterable, Identifiable {
        case songs
        case albums
        case artists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .songs: return "Songs"
            case .albums: return "Albums"
            case .artists: return "Artists"
            }
        }

        var searchPrompt: String {
            switch self {
            case .songs: return "Search songs"
            case .albums: return "Search albums"
            case .artists: return "Search artists"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $selectedDomain) {
                    ForEach(SearchDomain.allCases) { domain in
                        Text(domain.title).tag(domain)
                    }
                }
                .pickerStyle(.segmented)
            }

            if manager.isLoading && !manager.hasLoadedInitialSnapshot {
                LoadingListSection(title: "Indexing your media library…")
            } else if trimmedQuery.isEmpty {
                EmptyLibrarySection(
                    systemImage: "magnifyingglass",
                    title: "Search Your Library",
                    message: "Choose songs, albums, or artists and start typing to see matches."
                )
            } else {
                resultsContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.hasLoadedInitialSnapshot)
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(selectedDomain.searchPrompt))
    }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var resultsContent: some View {
        switch selectedDomain {
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
        return manager.librarySongs
            .filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var filteredAlbums: [TopAlbum] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return manager.libraryAlbums
            .filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.artist.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    private var filteredArtists: [TopArtist] {
        let query = trimmedQuery
        guard !query.isEmpty else { return [] }
        return manager.libraryArtists
            .filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    @ViewBuilder
    private var songsResults: some View {
        if filteredSongs.isEmpty {
            EmptyLibrarySection(
                systemImage: "music.note",
                title: "No Matching Songs",
                message: "Try a different title or artist."
            )
        } else {
            ForEach(filteredSongs) { song in
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
        if filteredAlbums.isEmpty {
            EmptyLibrarySection(
                systemImage: "rectangle.stack.badge.slash",
                title: "No Matching Albums",
                message: "We couldn't find albums that match your search."
            )
        } else {
            ForEach(filteredAlbums) { album in
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
        if filteredArtists.isEmpty {
            EmptyLibrarySection(
                systemImage: "person.crop.circle.badge.questionmark",
                title: "No Matching Artists",
                message: "Adjust your spelling or search for another artist."
            )
        } else {
            ForEach(filteredArtists) { artist in
                NavigationLink {
                    ArtistInfoView(artist: artist, manager: manager)
                } label: {
                    ArtistRow(artist: artist, sortMetric: manager.sortMetric)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LibrarySearchView(manager: MediaLibraryManager())
    }
}
