import AppIntents

struct PlayCountAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TopSongsIntent(),
            phrases: [
                "What are my top songs in \(.applicationName)",
                "Show my top music in \(.applicationName)",
                "Get my listening stats from \(.applicationName)"
            ],
            shortTitle: "Top Songs",
            systemImageName: "chart.bar"
        )

        AppShortcut(
            intent: SongPlayCountIntent(),
            phrases: [
                "How many times did I play \(\.$song) in \(.applicationName)",
                "Get the play count for \(\.$song) in \(.applicationName)",
                "Look up \(\.$song) in \(.applicationName)"
            ],
            shortTitle: "Song Play Count",
            systemImageName: "number"
        )

        AppShortcut(
            intent: CurrentSongStatsIntent(),
            phrases: [
                "How many times have I played this song in \(.applicationName)",
                "Get the current song stats from \(.applicationName)"
            ],
            shortTitle: "Current Song Stats",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: LatestRecapIntent(),
            phrases: [
                "Show my latest \(.applicationName) recap",
                "What was my listening recap in \(.applicationName)"
            ],
            shortTitle: "Latest Recap",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: BiggestGainerIntent(),
            phrases: [
                "What song climbed the most in \(.applicationName)",
                "Show my biggest gainer in \(.applicationName)"
            ],
            shortTitle: "Biggest Gainer",
            systemImageName: "arrow.up.right"
        )

        AppShortcut(
            intent: TopSongsThisMonthIntent(),
            phrases: [
                "What are my top songs this month in \(.applicationName)",
                "Show this month's top songs in \(.applicationName)"
            ],
            shortTitle: "Top This Month",
            systemImageName: "calendar.badge.clock"
        )

        AppShortcut(
            intent: TopArtistThisYearIntent(),
            phrases: [
                "Who is my top artist this year in \(.applicationName)",
                "Show my top artist of the year in \(.applicationName)"
            ],
            shortTitle: "Top Artist This Year",
            systemImageName: "person.crop.circle.badge.checkmark"
        )

        AppShortcut(
            intent: OpenLatestRecapIntent(),
            phrases: [
                "Open my latest recap in \(.applicationName)",
                "Open my \(.applicationName) recap"
            ],
            shortTitle: "Open Latest Recap",
            systemImageName: "arrow.up.forward.app"
        )
    }
}
