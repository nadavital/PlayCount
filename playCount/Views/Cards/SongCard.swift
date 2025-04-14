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
            ArtworkView(song: song)
                .padding(.trailing, 15)
            VStack(alignment: .leading) {
                Text(song.title)
                    .font(.subheadline)
                Text(song.artist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(song.playCount) Plays")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    SongCard(song: Song.preview)
}
