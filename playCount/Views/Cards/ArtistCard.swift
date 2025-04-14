import SwiftUI
import MediaPlayer

struct ArtistCard: View {
    let artist: Artist
    var body: some View {
        HStack {
            if let image = artist.artwork?.image(at: CGSize(width: 50, height: 50)) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 50, height: 50)
                    .cornerRadius(4)
            } else {
                Image(systemName: "person.crop.square")
                    .foregroundStyle(.secondary)
                    .frame(width: 50, height: 50)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    .shadow(radius: 10, x: 5, y: 5)
            }
            VStack(alignment: .leading) {
                Text(artist.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            Spacer()
            Text("\(artist.playCount) Plays")
                .font(.footnote.weight(.light))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ArtistCard(artist: Artist.preview)
}