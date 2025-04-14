// ...existing code...
import SwiftUI
import MediaPlayer

struct AlbumCard: View {
    let album: Album
    var body: some View {
        HStack {
            if let image = album.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .cornerRadius(4)
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(radius: 10, x: 5, y: 5)
            }
            VStack(alignment: .leading) {
                Text(album.title)
                    .font(.subheadline)
                Text(album.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(album.playCount) Plays")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    AlbumCard(album: Album.preview)
}
// ...existing code...