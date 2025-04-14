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
        topSongsList()
    }
}

#Preview {
    ContentView()
        .environmentObject(MediaPlayerManager())
}
