// ...existing code...
import SwiftUI
import MediaPlayer

struct topAlbumsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(topMusic.topAlbums, id: \.persistentID) { collection in
                    AlbumCard(album: Album(collection: collection))
                }
            }
        }
    }
}

#Preview {
    topAlbumsList()
        .environmentObject(MediaPlayerManager())
}
// ...existing code...