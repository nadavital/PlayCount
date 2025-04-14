import SwiftUI

struct SongRow: View {
    let song: Song
    let index: Int?
    var body: some View {
        NavigationLink(destination: SongInfoView(song: song)) {
            HStack(spacing: 12) {
                if let idx = index {
                    Text("\(idx + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                // Use artwork like AlbumTrackRow
                ArtworkView(artwork: song.artwork, fallbackSystemImage: "music.note", size: 40, cornerRadius: 8)
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(song.playCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SongRow(song: Song.preview, index: 1)
}
