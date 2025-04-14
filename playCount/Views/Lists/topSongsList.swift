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
    @State private var displayLimit = 50

    var filteredSongs: [MPMediaItem] {
        let baseList = searchText.isEmpty ? topMusic.topSongs : topMusic.topSongs.filter {
            $0.title?.localizedCaseInsensitiveContains(searchText) == true ||
            $0.artist?.localizedCaseInsensitiveContains(searchText) == true
        }
        return Array(baseList.prefix(displayLimit))
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
                if filteredSongs.count == displayLimit && filteredSongs.count < topMusic.topSongs.count {
                    Button("Load More") {
                        displayLimit += 50
                    }
                    .padding()
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
            }
        }
    }
}

#Preview {
    topSongsList(searchText: .constant(""))
        .environmentObject(MediaPlayerManager())
}
