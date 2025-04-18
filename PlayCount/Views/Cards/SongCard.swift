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
    SongCard(song: Song.preview, rank: 1)
}
