//
//  PlayCountApp.swift
//  PlayCount
//
//  Created by Nadav Avital on 9/19/25.
//

import SwiftUI
import AppIntents

@main
struct PlayCountApp: App {
    
    private var mediaLibraryManager: MediaLibraryManager
    
    init() {
        let mediaManager = MediaLibraryManager.shared
        mediaLibraryManager = mediaManager
        
        AppDependencyManager.shared.add(dependency: mediaManager)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
