import SwiftUI
import MediaPlayer

struct NowPlayingBar: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @State private var showSongInfo = false

    var body: some View {
        if let item = topMusic.nowPlayingItem {
            Button(action: { showSongInfo = true }) {
                HStack(spacing: 12) {
                    ArtworkView(artwork: item.artwork, fallbackSystemImage: "music.note", size: 48, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title ?? "Unknown Title")
                            .font(.headline)
                            .lineLimit(1)
                        Text(item.artist ?? "Unknown Artist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 16) {
                        Button(action: {
                            if topMusic.playbackState == .playing {
                                topMusic.pause()
                            } else {
                                topMusic.play()
                            }
                        }) {
                            Image(systemName: topMusic.playbackState == .playing ? "pause.fill" : "play.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button(action: { topMusic.next() }) {
                            Image(systemName: "forward.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.title2)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSongInfo) {
                if let item = topMusic.nowPlayingItem {
                    SongInfoView(song: Song(mediaItem: item))
                        .environmentObject(topMusic)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }
}
