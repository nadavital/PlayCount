// ...existing code...
import SwiftUI
import MediaPlayer

struct topArtistsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(topMusic.topArtists, id: \.persistentID) { collection in
                    ArtistCard(artist: Artist(collection: collection))
                }
            }
        }
    }
}

#Preview {
    topArtistsList()
        .environmentObject(MediaPlayerManager())
}
// ...existing code...