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
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
    
    init() {
        let mediaManager: MediaLibraryManager
        if Self.isRunningTests {
            mediaManager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        } else {
            mediaManager = MediaLibraryManager.shared
        }
        mediaLibraryManager = mediaManager
        
        AppDependencyManager.shared.add(dependency: mediaManager)
        if !Self.isRunningTests {
            RecapNotificationScheduler.shared.configure()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(libraryManager: mediaLibraryManager)
                .task {
                    if !Self.isRunningTests {
                        RecapBackgroundRefreshScheduler.schedule()
                    }
                }
        }
        .backgroundTask(.appRefresh(RecapBackgroundRefreshScheduler.identifier)) {
            RecapBackgroundRefreshScheduler.schedule()
            _ = await mediaLibraryManager.recordBackgroundRecapSnapshot()
        }
    }
}
