import SwiftUI

struct TopAlbumsView: View {
    let albums: [TopAlbum]
    let sortMetric: MediaLibraryManager.SortMetric
    let hasLoadedInitialSnapshot: Bool
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        List {
            if albums.isEmpty {
                if !hasLoadedInitialSnapshot {
                    LoadingListSection(title: "Loading your top albums…")
                } else {
                    EmptyLibrarySection(
                        systemImage: "rectangle.stack.badge.slash",
                        title: "No Albums Yet",
                        message: "Albums you listen to the most will show up once we detect play data."
                    )
                }
            } else {
                ForEach(Array(albums.enumerated()), id: \.element.id) { index, album in
                    NavigationLink {
                        AlbumInfoView(album: album, manager: manager)
                    } label: {
                        AlbumRow(album: album, sortMetric: sortMetric, rank: index + 1)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.2), value: hasLoadedInitialSnapshot)
    }
}

struct AlbumRow: View {
    let album: TopAlbum
    let sortMetric: MediaLibraryManager.SortMetric
    let rank: Int?

    init(album: TopAlbum, sortMetric: MediaLibraryManager.SortMetric, rank: Int? = nil) {
        self.album = album
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

            ArtworkView(artwork: album.artwork)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(album.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sortMetric.supplementaryDescription(playCount: album.playCount, duration: album.totalPlayDuration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: sortMetric.badgeText(playCount: album.playCount, duration: album.totalPlayDuration))
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
