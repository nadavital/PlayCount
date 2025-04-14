import SwiftUI
import MediaPlayer

struct topAlbumsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    var filteredAlbums: [MPMediaItemCollection] {
        if searchText.isEmpty {
            return topMusic.topAlbums
        } else {
            return topMusic.topAlbums.filter { collection in
                let albumTitle = collection.representativeItem?.albumTitle ?? ""
                let artist = collection.representativeItem?.artist ?? ""
                return albumTitle.localizedCaseInsensitiveContains(searchText) || artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(filteredAlbums, id: \.persistentID) { collection in
                    NavigationLink(destination: AlbumInfoView(album: Album(collection: collection))) {
                        AlbumCard(album: Album(collection: collection))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    topAlbumsList(searchText: .constant(""))
        .environmentObject(MediaPlayerManager())
}