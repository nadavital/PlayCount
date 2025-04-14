//
//  SongCard.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI
import MediaPlayer

struct SongCard: View {
    let song: Song
    var body: some View {
        HStack {
            ArtworkView(artwork: song.artwork)
                .padding(.trailing, 15)
            VStack(alignment: .leading) {
                Text(song.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Text(song.artist)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(song.playCount) Plays")
                .font(.footnote.weight(.light))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    SongCard(song: Song.preview)
}
