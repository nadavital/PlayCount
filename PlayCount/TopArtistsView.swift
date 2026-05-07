import SwiftUI

struct TopArtistsView: View {
    let artists: [TopArtist]
    let sortMetric: MediaLibraryManager.SortMetric
    let hasLoadedInitialSnapshot: Bool
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        List {
            if artists.isEmpty {
                if !hasLoadedInitialSnapshot {
                    LoadingListSection(title: "Loading your top artists…")
                } else {
                    EmptyLibrarySection(
                        systemImage: "person.crop.circle.badge.exclam",
                        title: "No Artists Yet",
                        message: "Your most-played artists will appear after you listen to music."
                    )
                }
            } else {
                ForEach(Array(artists.enumerated()), id: \.element.id) { index, artist in
                    NavigationLink {
                        ArtistInfoView(artist: artist, manager: manager)
                    } label: {
                        ArtistRow(artist: artist, sortMetric: sortMetric, rank: index + 1)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .animation(.easeInOut(duration: 0.2), value: hasLoadedInitialSnapshot)
    }
}

struct ArtistRow: View {
    let artist: TopArtist
    let sortMetric: MediaLibraryManager.SortMetric
    let rank: Int?

    init(artist: TopArtist, sortMetric: MediaLibraryManager.SortMetric, rank: Int? = nil) {
        self.artist = artist
        self.sortMetric = sortMetric
        self.rank = rank
    }

    var body: some View {
        MediaListRow(
            rank: rank,
            title: artist.name,
            detail: sortMetric.supplementaryDescription(playCount: artist.playCount, duration: artist.totalPlayDuration),
            badgeText: sortMetric.badgeText(playCount: artist.playCount, duration: artist.totalPlayDuration)
        ) {
            ArtistArtworkView(artwork: artist.artwork, name: artist.name)
        }
    }
}
