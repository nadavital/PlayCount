import SwiftUI
import MediaPlayer

struct topArtistsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
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
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(filteredArtists, id: \.persistentID) { collection in
                    NavigationLink(destination: ArtistInfoView(artist: Artist(collection: collection))) {
                        ArtistCard(artist: Artist(collection: collection))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    topArtistsList(searchText: .constant(""))
        .environmentObject(MediaPlayerManager())
}