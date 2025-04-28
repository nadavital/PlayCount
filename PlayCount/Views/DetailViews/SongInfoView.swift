import SwiftUI
import MediaPlayer

struct SongInfoView: View {
    let song: Song
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Environment(\.dismiss) private var dismiss
    
    // Helper to get the full Artist object
    var artistObject: Artist? {
        if let found = topMusic.topArtists.first(where: { $0.representativeItem?.artist == song.artist }) {
            return Artist(collection: found)
        }
        return Artist(name: song.artist)
    }
    // Helper to get the full Album object
    var albumObject: Album? {
        if let found = topMusic.topAlbums.first(where: { $0.representativeItem?.albumTitle == song.albumTitle && $0.representativeItem?.artist == song.artist }) {
            return Album(collection: found)
        }
        return Album(title: song.albumTitle, artist: song.artist)
    }
    
    var genre: String {
        song.mediaItem?.genre ?? "Unknown Genre"
    }
    
    var releaseDate: String {
        if let date = song.mediaItem?.releaseDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
        return "Unknown Release Date"
    }
    
    var duration: String {
        guard let seconds = song.mediaItem?.playbackDuration else { return "--:--" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var gradient: LinearGradient {
        if let image = song.artwork?.image(at: CGSize(width: 40, height: 40)),
           let avgColor = image.averageColor {
            return LinearGradient(
                gradient: Gradient(colors: [Color(avgColor).opacity(0.55), Color(.systemGroupedBackground)]),
                startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.25), Color(.systemGroupedBackground)]),
                startPoint: .top, endPoint: .bottom)
        }
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 24) {
                    ArtworkView(
                        artwork: song.artwork,
                        fallbackSystemImage: "music.note",
                        size: 280,
                        cornerRadius: 32
                    )
                    // Top Section: Title + Play Button, then Artist/Album, then Play Count
                    VStack(spacing: 8) {
                        // Title and Play Button in HStack
                        HStack(alignment: .center, spacing: 12) {
                            Text(song.title)
                                .font(.largeTitle).bold()
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                            Button(action: {
                                if let item = song.mediaItem {
                                    if topMusic.nowPlayingItem?.persistentID == item.persistentID && topMusic.playbackState == .playing {
                                        topMusic.pause()
                                    } else {
                                        topMusic.play(item: item)
                                    }
                                }
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 48, height: 48)
                                    Image(systemName: (topMusic.nowPlayingItem?.persistentID == song.mediaItem?.persistentID && topMusic.playbackState == .playing) ? "pause.fill" : "play.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(Color.black)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        // Artist and Album below
                        VStack(spacing: 2) {
                            if let artist = artistObject {
                                NavigationLink(destination: ArtistInfoView(artist: artist)) {
                                    Text(song.artist)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(song.artist)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            if let album = albumObject {
                                NavigationLink(destination: AlbumInfoView(album: album)) {
                                    Text(song.albumTitle)
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(song.albumTitle)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        // Play Count below artist/album
                        VStack(spacing: 2) {
                            Text("\(song.playCount)")
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
                        Label { Text(duration) } icon: { Image(systemName: "clock") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
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
    SongInfoViewPreview.previews
}

@MainActor
private struct SongInfoViewPreview {
    static var previews: some View {
        let manager = MediaPlayerManager.previewManager
        let item = manager.topSongs.first!
        let song = Song(mediaItem: item)
        return NavigationStack {
            SongInfoView(song: song)
                .environmentObject(manager)
        }
    }
}
