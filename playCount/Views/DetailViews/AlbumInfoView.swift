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
                // Top Section: Title + Play Button, then Artist, then Play Count
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(album.title)
                            .font(.largeTitle).bold()
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Button(action: {
                            if let first = album.items.first {
                                let isCurrentAlbum = topMusic.nowPlayingItem?.albumTitle == album.title && topMusic.nowPlayingItem?.artist == album.artist
                                if (isCurrentAlbum && topMusic.playbackState == .playing) {
                                    topMusic.pause()
                                } else {
                                    topMusic.play(collection: MPMediaItemCollection(items: album.items))
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 48, height: 48)
                                let isCurrentAlbum = topMusic.nowPlayingItem?.albumTitle == album.title && topMusic.nowPlayingItem?.artist == album.artist
                                Image(systemName: (isCurrentAlbum && topMusic.playbackState == .playing) ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(Color.black)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    // Artist below
                    if let artist = artistObject {
                        NavigationLink(destination: ArtistInfoView(artist: artist)) {
                            Text(album.artist)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(album.artist)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    // Play Count below artist
                    VStack(spacing: 2) {
                        Text("\(album.playCount)")
                            .font(.title.bold())
                            .foregroundStyle(.primary)
                        Text("Plays")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                // Other Info
                HStack(spacing: 20) {
                    Label { Text(genre) } icon: { Image(systemName: "guitars") }
                    Label { Text(releaseDate) } icon: { Image(systemName: "calendar") }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
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
