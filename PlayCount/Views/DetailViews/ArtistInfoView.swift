import SwiftUI
import MediaPlayer

struct ArtistInfoView: View {
    let artist: Artist
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Environment(\.dismiss) private var dismiss
    
    // Top songs sorted by play count
    var topSongs: [MPMediaItem] {
        artist.items.sorted { $0.playCount > $1.playCount }
    }
    // Top albums: get from MediaPlayerManager, filter by artist, sort by play count, take top 5
    var topAlbums: [Album] {
        topMusic.topAlbums
            .filter { $0.representativeItem?.artist == artist.name }
            .sorted { $0.items.reduce(0) { $0 + $1.playCount } > $1.items.reduce(0) { $0 + $1.playCount } }
            .prefix(5)
            .map { Album(collection: $0) }
    }
    
    var gradient: LinearGradient {
        if let image = artist.artwork?.image(at: CGSize(width: 40, height: 40)),
           let avgColor = image.averageColor {
            return LinearGradient(
                gradient: Gradient(colors: [Color(avgColor).opacity(0.55), Color(.systemGroupedBackground)]),
                startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.purple.opacity(0.25), Color(.systemGroupedBackground)]),
                startPoint: .top, endPoint: .bottom)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 24) {
                    ArtworkView(
                        artwork: artist.artwork,
                        fallbackSystemImage: "person.crop.square",
                        size: 280,
                        cornerRadius: 32
                    )
                    // Top Section: Title + Play Button, then Play Count
                    VStack(spacing: 8) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(artist.name)
                                .font(.largeTitle).bold()
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            Button(action: {
                                let artistSongs = artist.items
                                let isCurrentArtist = topMusic.nowPlayingItem?.artist == artist.name
                                if isCurrentArtist && topMusic.playbackState == .playing {
                                    topMusic.pause()
                                } else {
                                    topMusic.play(collection: MPMediaItemCollection(items: artistSongs))
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 48, height: 48)
                                    let isCurrentArtist = topMusic.nowPlayingItem?.artist == artist.name
                                    Image(systemName: (isCurrentArtist && topMusic.playbackState == .playing) ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(Color.black)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        // Play Count below title
                        VStack(spacing: 2) {
                            Text("\(artist.playCount)")
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
                    // Top Albums List
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Top Albums")
                            .font(.title2).bold()
                            .padding(.bottom, 8)
                        VStack(spacing: 0) {
                            ForEach(topAlbums.indices, id: \.self) { idx in
                                let album = topAlbums[idx]
                                NavigationLink(destination: AlbumInfoView(album: album).environmentObject(topMusic)) {
                                    AlbumRow(album: album, index: idx)
                                }
                                .buttonStyle(.plain)
                                if idx < topAlbums.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 4)
                    }
                    .padding(.top, 8)
                    // Top Songs List
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Top Songs")
                            .font(.title2).bold()
                            .padding(.bottom, 8)
                        VStack(spacing: 0) {
                            ForEach(topSongs.prefix(5).indices, id: \.self) { idx in
                                let song = Song(mediaItem: topSongs[idx])
                                SongRow(song: song, index: idx)
                                if idx < min(topSongs.count, 5) - 1 {
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
            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 40, height: 40)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.leading, 16)
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    ArtistInfoView_Preview.previews
}

@MainActor
private struct ArtistInfoView_Preview {
    static var previews: some View {
        let manager = MediaPlayerManager.previewManager
        let collection = manager.topArtists.first!
        let artist = Artist(collection: collection)
        return NavigationStack {
            ArtistInfoView(artist: artist)
                .environmentObject(manager)
        }
    }
}
