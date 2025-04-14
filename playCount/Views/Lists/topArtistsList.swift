import SwiftUI
import MediaPlayer

struct topArtistsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @State private var searchText = ""
    var filteredArtists: [MPMediaItemCollection] {
        if searchText.isEmpty {
            return topMusic.topArtists
        } else {
            return topMusic.topArtists.filter { collection in
                let artist = collection.representativeItem?.artist ?? ""
                return artist.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack {
                    ForEach(filteredArtists, id: \.persistentID) { collection in
                        ArtistCard(artist: Artist(collection: collection))
                    }
                }
            }
            .navigationTitle("Top Artists")
            .searchable(text: $searchText, prompt: "Search Artists")
        }
    }
}

#Preview {
    topArtistsList()
        .environmentObject(MediaPlayerManager())
}