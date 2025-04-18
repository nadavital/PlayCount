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
                ForEach(Array(filteredArtists.enumerated()), id: \.element.persistentID) { index, collection in
                    NavigationLink(destination: ArtistInfoView(artist: Artist(collection: collection))) {
                        ArtistCard(artist: Artist(collection: collection), rank: index + 1)
                    }
                    .buttonStyle(.plain)
                }
                if filteredArtists.count == displayLimit && filteredArtists.count < topMusic.topArtists.count {
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

#Preview {
    topArtistsList(searchText: .constant(""))
        .environmentObject(MediaPlayerManager())
}