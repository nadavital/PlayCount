//
//  PlayCountAppShortcuts.swift
//  PlayCount
//
//  Created by Nadav Avital on 9/25/25.
//

import Foundation
import AppIntents

struct PlayCountAppShortcuts: AppShortcutsProvider {
    
    static var appShortcuts: [AppShortcut] {
        
        AppShortcut(intent: TopFiveSongsIntent(),
                    phrases: [
                        "Get my top five songs from \(.applicationName)",
                        "What are my top songs in \(.applicationName)",
                        "Get my \(.applicationName) stats"
                    ],
                    shortTitle: "Top Songs",
                    systemImageName: "music.note")
        
        AppShortcut(intent: CurrentSongPlayCountIntent(),
                    phrases: [
                        "How many times have I listened to this song in \(.applicationName)?",
                        "How many times have I played this song in \(.applicationName)?",
                        "What's the \(.applicationName) of this song?"
                    ],
                    shortTitle: "Current Song Play Count",
                    systemImageName: "music.quarternote.3"
        )
        
        AppShortcut(
            intent: SearchPlayCountIntent(),
            phrases: [
                "Find me a \(.applicationName)",
                "Get me a \(.applicationName)",
                "Find a \(.applicationName)",
                "Get a \(.applicationName)",
                "Look up a \(.applicationName)",
                "Look up a \(.applicationName) for me"
            ],
            shortTitle: "Search PlayCount",
            systemImageName: "magnifyingglass"
        )
    }
    
}
