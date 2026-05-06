//
//  PlayCountApp.swift
//  PlayCount
//
//  Created by Nadav Avital on 9/19/25.
//

import SwiftUI
import AppIntents
import BackgroundTasks

@main
struct PlayCountApp: App {
    
    private var mediaLibraryManager: MediaLibraryManager
    
    init() {
        let mediaManager = MediaLibraryManager.shared
        mediaLibraryManager = mediaManager
        
        AppDependencyManager.shared.add(dependency: mediaManager)
        RecapNotificationScheduler.shared.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(libraryManager: mediaLibraryManager)
                .task {
                    RecapBackgroundRefreshScheduler.schedule()
                }
        }
        .backgroundTask(.appRefresh(RecapBackgroundRefreshScheduler.identifier)) {
            RecapBackgroundRefreshScheduler.schedule()
            _ = await mediaLibraryManager.recordBackgroundRecapSnapshot()
        }
    }
}
