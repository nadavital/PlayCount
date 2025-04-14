import SwiftUI

struct SongInfoView: View {
    let song: Song
    @EnvironmentObject private var topMusic: MediaPlayerManager
    
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
        ScrollView {
            VStack(spacing: 24) {
                ArtworkView(
                    artwork: song.artwork,
                    fallbackSystemImage: "music.note",
                    size: 280,
                    cornerRadius: 32
                )
                // Song Details Card with Play Button
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title)
                            .font(.largeTitle).bold()
                            .multilineTextAlignment(.leading)
                        // Artist NavigationLink
                        if let artist = artistObject {
                            NavigationLink(destination: ArtistInfoView(artist: artist)) {
                                Text(song.artist)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(song.artist)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.secondary)
                        }
                        // Album NavigationLink
                        if let album = albumObject {
                            NavigationLink(destination: AlbumInfoView(album: album)) {
                                Text(song.albumTitle)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(song.albumTitle)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)
                    Button(action: {
                        if let item = song.mediaItem {
                            if topMusic.nowPlayingItem?.persistentID == item.persistentID && topMusic.playbackState == .playing {
                                topMusic.pause()
                            } else {
                                topMusic.play(item: item)
                            }
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: (topMusic.nowPlayingItem?.persistentID == song.mediaItem?.persistentID && topMusic.playbackState == .playing) ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 44))
                            Text((topMusic.nowPlayingItem?.persistentID == song.mediaItem?.persistentID && topMusic.playbackState == .playing) ? "Pause" : "Play")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 20) {
                        Label { Text("\(song.playCount)") } icon: { Image(systemName: "play.circle.fill") }
                        Label { Text(genre) } icon: { Image(systemName: "guitars") }
                        Label { Text(releaseDate) } icon: { Image(systemName: "calendar") }
                        Label { Text(duration) } icon: { Image(systemName: "clock") }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(gradient.ignoresSafeArea())
    }
}

#Preview {
    SongInfoView(song: Song.preview)
}
