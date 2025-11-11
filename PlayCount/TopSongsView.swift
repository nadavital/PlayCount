import SwiftUI

struct TopSongsView: View {
    let songs: [TopSong]
    let sortMetric: MediaLibraryManager.SortMetric
    let hasLoadedInitialSnapshot: Bool
    @ObservedObject var manager: MediaLibraryManager

    var body: some View {
        List {
            if songs.isEmpty {
                if !hasLoadedInitialSnapshot {
                    LoadingListSection(title: "Loading your top songs…")
                } else {
                    EmptyLibrarySection(
                        systemImage: "music.note.slash",
                        title: "No Plays Yet",
                        message: "Play songs from your library to see them ranked here."
                    )
                }
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    NavigationLink {
                        SongInfoView(song: song, manager: manager)
                    } label: {
                        SongRow(song: song, sortMetric: sortMetric, rank: index + 1)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.2), value: hasLoadedInitialSnapshot)
    }
}

struct SongRow: View {
    let song: TopSong
    let sortMetric: MediaLibraryManager.SortMetric
    let rank: Int?

    init(song: TopSong, sortMetric: MediaLibraryManager.SortMetric, rank: Int? = nil) {
        self.song = song
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

            ArtworkView(artwork: song.artwork)

            VStack(alignment: .leading, spacing: 4) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(sortMetric.supplementaryDescription(playCount: song.playCount, duration: song.totalPlayDuration))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            MetricBadge(text: sortMetric.badgeText(playCount: song.playCount, duration: song.totalPlayDuration))
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
