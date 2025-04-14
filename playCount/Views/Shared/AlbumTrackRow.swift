import SwiftUI

struct AlbumTrackRow: View {
    let song: Song
    let index: Int?
    var body: some View {
        NavigationLink(destination: SongInfoView(song: song)) {
            HStack(spacing: 12) {
                // Track number
                if let idx = index {
                    Text("\(idx + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                // Title
                Text(song.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                // Play count and chevron
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
    AlbumTrackRow(song: Song.preview, index: 1)
}
