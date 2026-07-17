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
                    LoadingListSection(title: manager.loadingStage.message ?? "Loading your top songs…")
                } else {
                    EmptyLibrarySection(
                        systemImage: "music.note.slash",
                        title: "No Plays Yet",
                        message: "Play songs from your library to see them ranked here."
                    )
                }
            } else {
                if let monthlySong = manager.monthlyRecap.topSongs.first,
                   let resolvedSong = manager.song(withPersistentID: monthlySong.id)
                    ?? manager.song(matchingTitle: monthlySong.title, artist: monthlySong.artist) {
                    Section("This Month") {
                        NavigationLink {
                            SongInfoView(song: resolvedSong, manager: manager)
                        } label: {
                            MonthlyInsightRow(
                                eyebrow: "Most Played",
                                title: monthlySong.title,
                                subtitle: monthlySong.artist,
                                metric: "+\(monthlySong.playDelta)"
                            ) {
                                ArtworkView(
                                    artwork: monthlySong.artwork ?? resolvedSong.artwork,
                                    size: CGSize(width: 58, height: 58),
                                    cornerRadius: 11
                                )
                            }
                        }
                    }
                }

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
        .scrollIndicators(.hidden)
        .refreshable {
            manager.refreshTopItems()
        }
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
        MediaListRow(
            rank: rank,
            title: song.title,
            subtitle: song.artist,
            detail: sortMetric.supplementaryDescription(playCount: song.playCount, duration: song.totalPlayDuration),
            badgeText: sortMetric.badgeText(playCount: song.playCount, duration: song.totalPlayDuration)
        ) {
            ArtworkView(artwork: song.artwork)
        }
    }
}
