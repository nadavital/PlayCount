//
//  playCountApp.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI

@main
struct PlayCountApp: App {
    @StateObject private var topMusic = MediaPlayerManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(topMusic)
        }
    }
}
