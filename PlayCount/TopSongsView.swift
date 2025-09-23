import SwiftUI

struct TopSongsView: View {
    let songs: [TopSong]
    let sortMetric: MediaLibraryManager.SortMetric
    let hasLoadedInitialSnapshot: Bool

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
                ForEach(songs) { song in
                    NavigationLink {
                        SongInfoView(song: song)
                    } label: {
                        SongRow(song: song, sortMetric: sortMetric)
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

    var body: some View {
        HStack(spacing: 12) {
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
}
