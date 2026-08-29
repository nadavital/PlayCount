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
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement

    var body: some View {
        HStack(spacing: isInline ? 8 : 12) {
            ArtworkView(artwork: state.artwork, size: artworkSize)
                .id(state.song?.id)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if !isInline {
                    Text(state.subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            if !isInline, let playCountText {
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
        .padding(.vertical, isInline ? 3 : 6)
        .padding(.horizontal, isInline ? 10 : 20)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("now-playing-accessory")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens the current song details"))
        .onTapGesture {
            onTap?(state)
        }
    }

    private var isInline: Bool {
        accessoryPlacement == .inline
    }

    private var artworkSize: CGSize {
        let side: CGFloat = isInline ? 28 : 36
        return CGSize(width: side, height: side)
    }

    private var playCountText: String? {
        guard let song = state.song else { return nil }
        return "\(song.playCount.detailFormatted) plays"
    }
}
