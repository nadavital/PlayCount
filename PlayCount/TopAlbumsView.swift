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
                    LoadingListSection(title: manager.loadingStage.message ?? "Loading your top albums…")
                } else {
                    EmptyLibrarySection(
                        systemImage: "rectangle.stack.badge.slash",
                        title: "No Albums Yet",
                        message: "Albums you listen to the most will show up once we detect play data."
                    )
                }
            } else {
                if let monthlyAlbum = manager.monthlyRecap.topAlbums.first,
                   let resolvedAlbum = UInt64(monthlyAlbum.id).flatMap(manager.album(withPersistentID:))
                    ?? manager.album(matchingTitle: monthlyAlbum.title, artist: monthlyAlbum.subtitle) {
                    Section("This Month") {
                        NavigationLink {
                            AlbumInfoView(album: resolvedAlbum, manager: manager)
                        } label: {
                            MonthlyInsightRow(
                                eyebrow: "Top Album",
                                title: monthlyAlbum.title,
                                subtitle: monthlyAlbum.subtitle,
                                metric: "+\(monthlyAlbum.playDelta)"
                            ) {
                                ArtworkView(
                                    artwork: monthlyAlbum.artwork ?? resolvedAlbum.artwork,
                                    size: CGSize(width: 58, height: 58),
                                    cornerRadius: 11
                                )
                            }
                        }
                    }
                }

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
        .scrollIndicators(.hidden)
        .refreshable {
            manager.refreshTopItems()
        }
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
        MediaListRow(
            rank: rank,
            title: album.title,
            subtitle: album.artist,
            detail: sortMetric.supplementaryDescription(playCount: album.playCount, duration: album.totalPlayDuration),
            badgeText: sortMetric.badgeText(playCount: album.playCount, duration: album.totalPlayDuration)
        ) {
            ArtworkView(artwork: album.artwork)
        }
    }
}
