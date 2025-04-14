import SwiftUI
import MediaPlayer

struct topAlbumsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @State private var searchText = ""
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
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack {
                    ForEach(filteredAlbums, id: \.persistentID) { collection in
                        AlbumCard(album: Album(collection: collection))
                    }
                }
            }
            .navigationTitle("Top Albums")
            .searchable(text: $searchText, prompt: "Search Albums or Artists")
        }
    }
}

#Preview {
    topAlbumsList()
        .environmentObject(MediaPlayerManager())
}