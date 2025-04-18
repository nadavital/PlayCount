import SwiftUI

struct AlbumRow: View {
    let album: Album
    let index: Int?
    var body: some View {
        NavigationLink(destination: AlbumInfoView(album: album)) {
            HStack(spacing: 12) {
                if let idx = index {
                    Text("\(idx + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                // Use artwork from album's representative item
                ArtworkView(artwork: album.artwork, fallbackSystemImage: "rectangle.stack.fill", size: 40, cornerRadius: 8)
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Image(systemName: "play.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(album.playCount)")
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
    AlbumRow(album: Album.preview, index: 1)
}
