//
//  topSongsList.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI

struct topSongsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(topMusic.topSongs, id: \.persistentID) { song in
                    SongCard(song: Song(mediaItem: song))
                }
            }
        }
    }
}

#Preview {
    topSongsList()
        .environmentObject(MediaPlayerManager())
}
