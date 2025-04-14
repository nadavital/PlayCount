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
    @State private var searchText = ""
    var filteredSongs: [MPMediaItem] {
        if searchText.isEmpty {
            return topMusic.topSongs
        } else {
            return topMusic.topSongs.filter { $0.title?.localizedCaseInsensitiveContains(searchText) == true || $0.artist?.localizedCaseInsensitiveContains(searchText) == true }
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack {
                    ForEach(filteredSongs, id: \.persistentID) { song in
                        SongCard(song: Song(mediaItem: song))
                    }
                }
            }
            .navigationTitle("Top Songs")
            .searchable(text: $searchText, prompt: "Search Songs or Artists")
        }
    }
}

#Preview {
    topSongsList()
        .environmentObject(MediaPlayerManager())
}
