import SwiftUI

struct NowPlayingBarView: View {
    @ObservedObject var manager: MediaLibraryManager
    var onTap: ((MediaLibraryManager.NowPlayingState) -> Void)? = nil

    var body: some View {
        if let state = manager.nowPlayingState {
            NowPlayingBarContent(state: state, manager: manager, onTap: onTap)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

private struct NowPlayingBarContent: View {
    let state: MediaLibraryManager.NowPlayingState
    @ObservedObject var manager: MediaLibraryManager
    var onTap: ((MediaLibraryManager.NowPlayingState) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: state.artwork, size: CGSize(width: 36, height: 36))
                .id(state.song?.id)

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
            .layoutPriority(1)

            Spacer(minLength: 8)

            if let playCountText {
                Text(playCountText)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Button(action: manager.togglePlayback) {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.symbolEffect(.replace))
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

    private var playCountText: String? {
        guard let song = state.song else { return nil }
        return "\(song.playCount.detailFormatted) plays"
    }
}
