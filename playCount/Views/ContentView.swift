//
//  ContentView.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var topMusic: MediaPlayerManager
    var body: some View {
        TabView {
            topSongsList()
                .tabItem {
                    Label("Songs", systemImage: "music.note")
                }
            topAlbumsList()
                .tabItem {
                    Label("Albums", systemImage: "rectangle.stack")
                }
            topArtistsList()
                .tabItem {
                    Label("Artists", systemImage: "person.2")
                }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MediaPlayerManager())
}
