import SwiftUI
import MediaPlayer

struct topAlbumsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    @State private var displayLimit = 50

    var filteredAlbums: [MPMediaItemCollection] {
        let baseList = searchText.isEmpty ? topMusic.topAlbums : topMusic.topAlbums.filter {
            let albumTitle = $0.representativeItem?.albumTitle ?? ""
            let artist = $0.representativeItem?.artist ?? ""
            return albumTitle.localizedCaseInsensitiveContains(searchText) || artist.localizedCaseInsensitiveContains(searchText)
        }
        return Array(baseList.prefix(displayLimit))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(Array(filteredAlbums.enumerated()), id: \.offset) { index, collection in
                    NavigationLink(destination: AlbumInfoView(album: Album(collection: collection))) {
                        AlbumCard(album: Album(collection: collection), rank: index + 1)
                    }
                    .buttonStyle(.plain)
                }
                if filteredAlbums.count == displayLimit && filteredAlbums.count < topMusic.topAlbums.count {
                    Button("Load More") {
                        displayLimit += 50
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 20)
                    .background(.ultraThinMaterial, in: Capsule())
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

#if DEBUG
#Preview {
    TopAlbumsListPreview.previews
}

@MainActor
private struct TopAlbumsListPreview {
    static var previews: some View {
        topAlbumsList(searchText: .constant(""))
            .environmentObject(MediaPlayerManager.previewManager)
    }
}
#endif