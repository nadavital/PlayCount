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
                ForEach(artists) { artist in
                    NavigationLink {
                        ArtistInfoView(artist: artist, manager: manager)
                    } label: {
                        ArtistRow(artist: artist, sortMetric: sortMetric)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.2), value: hasLoadedInitialSnapshot)
    }
}

struct ArtistRow: View {
    let artist: TopArtist
    let sortMetric: MediaLibraryManager.SortMetric

    var body: some View {
        HStack(spacing: 12) {
            ArtistArtworkView(artwork: artist.artwork, name: artist.name)

            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(sortMetric.supplementaryDescription(playCount: artist.playCount, duration: artist.totalPlayDuration))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: sortMetric.badgeText(playCount: artist.playCount, duration: artist.totalPlayDuration))
        }
        .padding(.vertical, 4)
    }
}
