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

    private static var shouldScheduleBackgroundWork: Bool {
        #if DEBUG
        !isRunningTests && !StartupVerification.isEnabled
        #else
        !isRunningTests
        #endif
    }
    
    init() {
        let mediaManager: MediaLibraryManager
        if Self.isRunningTests {
            mediaManager = MediaLibraryManager(recapCloudSyncService: nil, startsAutomatically: false)
        } else {
            #if DEBUG
            mediaManager = StartupVerification.isEnabled
                ? StartupVerification.makeManager()
                : MediaLibraryManager.shared
            #else
            mediaManager = MediaLibraryManager.shared
            #endif
        }
        mediaLibraryManager = mediaManager
        
        AppDependencyManager.shared.add(dependency: mediaManager)
        if Self.shouldScheduleBackgroundWork {
            RecapNotificationScheduler.shared.configure()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(libraryManager: mediaLibraryManager)
                .tint(PlayCountBrand.accent)
                .task {
                    if Self.shouldScheduleBackgroundWork {
                        RecapBackgroundRefreshScheduler.schedule()
                    }
                }
        }
        .backgroundTask(.appRefresh(RecapBackgroundRefreshScheduler.identifier)) {
            RecapBackgroundRefreshScheduler.schedule()
            if let update = await mediaLibraryManager.recordBackgroundRecapSnapshot() {
                await RecapNotificationScheduler.shared.scheduleBackgroundUpdate(update)
            }
        }
    }
}
