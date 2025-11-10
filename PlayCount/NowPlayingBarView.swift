import SwiftUI

struct NowPlayingBarView: View {
    @ObservedObject var manager: MediaLibraryManager
    var onTap: ((MediaLibraryManager.NowPlayingState) -> Void)? = nil

    var body: some View {
        Group {
            if let state = manager.nowPlayingState {
                HStack(spacing: 12) {
                    ArtworkView(artwork: state.artwork, size: CGSize(width: 36, height: 36))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(state.subtitle)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Button(action: manager.togglePlayback) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 20)
                .contentShape(Rectangle())
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(Text("Opens the current song details"))
                .onTapGesture {
                    onTap?(state)
                }
            }
        }
    }
}
