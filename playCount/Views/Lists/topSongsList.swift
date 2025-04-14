//
//  topSongsList.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI
import MediaPlayer

struct topSongsList: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    @Binding var searchText: String
    var filteredSongs: [MPMediaItem] {
        if searchText.isEmpty {
            return topMusic.topSongs
        } else {
            return topMusic.topSongs.filter { $0.title?.localizedCaseInsensitiveContains(searchText) == true || $0.artist?.localizedCaseInsensitiveContains(searchText) == true }
        }
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack {
                ForEach(filteredSongs, id: \.persistentID) { song in
                    NavigationLink(destination: SongInfoView(song: Song(mediaItem: song))) {
                        SongCard(song: Song(mediaItem: song))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    topSongsList(searchText: .constant(""))
        .environmentObject(MediaPlayerManager())
}
