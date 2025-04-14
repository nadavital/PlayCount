import SwiftUI
import MediaPlayer

struct AlbumInfoView: View {
    let album: Album
    @EnvironmentObject private var topMusic: MediaPlayerManager
    
    var genre: String {
        album.items.first?.genre ?? "Unknown Genre"
    }
    
    var releaseDate: String {
        if let date = album.items.first?.releaseDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
        return "Unknown Release Date"
    }
    
    // Helper to get the Artist object for NavigationLink
    var artistObject: Artist? {
        // Try to find the artist in the topMusic manager
        if let found = topMusic.topArtists.first(where: { $0.representativeItem?.artist == album.artist }) {
            return Artist(collection: found)
        }
        // Fallback: create a minimal Artist from album info
        return Artist(name: album.artist)
    }
    
    var body: some View {
        let gradient: LinearGradient = {
            if let image = album.artwork?.image(at: CGSize(width: 40, height: 40)),
               let avgColor = image.averageColor {
                return LinearGradient(
                    gradient: Gradient(colors: [Color(avgColor).opacity(0.55), Color(.systemGroupedBackground)]),
                    startPoint: .top, endPoint: .bottom)
            } else {
                return LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.25), Color(.systemGroupedBackground)]),
                    startPoint: .top, endPoint: .bottom)
            }
        }()
        ScrollView {
            VStack(spacing: 24) {
                ArtworkView(
                    artwork: album.artwork,
                    fallbackSystemImage: "rectangle.stack.fill",
                    size: 280,
                    cornerRadius: 32
                )
                // Album Details Card
                VStack(spacing: 12) {
                    Text(album.title)
                        .font(.largeTitle).bold()
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                    // Artist NavigationLink
                    if let artist = artistObject {
                        NavigationLink(destination: ArtistInfoView(artist: artist)) {
                            Text(album.artist)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(album.artist)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 20) {
                        Label { Text("\(album.playCount)") } icon: { Image(systemName: "play.circle.fill") }
                        Label { Text(genre) } icon: { Image(systemName: "guitars") }
                        Label { Text(releaseDate) } icon: { Image(systemName: "calendar") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                // Tracks List
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tracks")
                        .font(.title2).bold()
                        .padding(.bottom, 8)
                    VStack(spacing: 0) {
                        ForEach(album.items.indices, id: \.self) { idx in
                            let track = album.items[idx]
                            AlbumTrackRow(song: Song(mediaItem: track), index: idx)
                            if idx < album.items.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.bottom, 4)
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .background(gradient.ignoresSafeArea())
    }
}

#Preview {
    AlbumInfoView(album: Album.preview)
        .environmentObject(MediaPlayerManager())
}
