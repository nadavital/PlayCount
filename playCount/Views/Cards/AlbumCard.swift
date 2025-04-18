import SwiftUI
import MediaPlayer

struct AlbumCard: View {
    let album: Album
    let rank: Int
    var body: some View {
        HStack {
            // display ranking with special badge
            ZStack {
                if rank <= 3 {
                    Circle()
                        .fill(rank == 1 ? Color.yellow : rank == 2 ? Color.gray : Color(red:205/255, green:127/255, blue:50/255))
                }
                Text("\(rank)")
                    .font(.subheadline.bold())
                    .foregroundColor(rank <= 3 ? Color.white : Color.secondary)
            }
            .frame(width: 30, height: 30)
            
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
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(album.artist)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(album.playCount) Plays")
                .font(.footnote.weight(.light))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    AlbumCard(album: Album.preview, rank: 1)
}