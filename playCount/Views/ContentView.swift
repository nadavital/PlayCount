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
            TopSongsView()
                .tabItem {
                    Label("Songs", systemImage: "music.note")
                }
            TopAlbumsView()
                .tabItem {
                    Label("Albums", systemImage: "rectangle.stack")
                }
            TopArtistsView()
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
