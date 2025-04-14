import SwiftUI
import MediaPlayer

struct topArtistsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    @State private var displayLimit = 50

    var filteredArtists: [MPMediaItemCollection] {
        let baseList = searchText.isEmpty ? topMusic.topArtists : topMusic.topArtists.filter {
            let artist = $0.representativeItem?.artist ?? ""
            return artist.localizedCaseInsensitiveContains(searchText)
        }
        return Array(baseList.prefix(displayLimit))
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
                if filteredArtists.count == displayLimit && filteredArtists.count < topMusic.topArtists.count {
                    Button("Load More") {
                        displayLimit += 50
                    }
                    .padding()
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
}

#Preview {
    topArtistsList(searchText: .constant(""))
        .environmentObject(MediaPlayerManager())
}