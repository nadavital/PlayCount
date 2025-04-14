//
//  playCountApp.swift
//  playCount
//
//  Created by Nadav Avital on 4/8/25.
//

import SwiftUI

@main
struct playCountApp: App {
    @StateObject private var topMusic = MediaPlayerManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(topMusic)
        }
    }
}
