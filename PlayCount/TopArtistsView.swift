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
        HStack(spacing: 12) {
            if let rank = rank {
                if rank <= 3 {
                    Text(medalForRank(rank))
                        .font(.system(size: 20))
                        .frame(minWidth: 24, alignment: .trailing)
                } else {
                    Text("\(rank)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                        .monospacedDigit()
                }
            }

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

    private func medalForRank(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }
}
