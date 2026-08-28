<p align="center">
  <img src="PlayCount/PlayCountShareIcon.png" width="112" alt="PlayCount medal icon">
</p>

# PlayCount

PlayCount turns the play counts in an Apple Music library into a personal listening history. It ranks songs, albums, and artists, builds monthly and yearly recaps, tracks milestones, and makes the results easy to explore and share.

[View PlayCount on the App Store](https://apps.apple.com/app/id6744829166)

## Highlights

- Rank songs, albums, and artists by plays or estimated listening time.
- Browse artwork-first detail pages and start playback through the system Music player.
- Build incremental monthly and yearly recaps without retaining an unbounded history of raw snapshots.
- Preserve recap history across library removals, re-additions, partial scans, and iCloud sync.
- Compare weekly and monthly listening trends, biggest gainers, and collectible milestones.
- Share branded recap cards.
- Expose listening stats through App Intents, Spotlight, Shortcuts, and iOS 27 Siri integrations.

## How it works

The app is written in SwiftUI and uses `MediaPlayer` as the source of local Apple Music library metadata and cumulative play counts. Period-specific recaps are derived from incremental snapshots and folded into durable monthly ledgers. Recap data is stored locally and can sync through the user's private CloudKit database.

Apple does not expose a complete per-play event history through `MediaPlayer`, so PlayCount cannot reconstruct listening that happened before it began tracking. The recap system is designed around that API boundary instead of implying unavailable precision.

## Building

Requirements:

- Xcode 27 or newer
- iOS 26 or newer
- An Apple developer team for device signing

Open `PlayCount.xcodeproj`, choose your development team, and run the `PlayCount` scheme. To use CloudKit under your own account, replace the bundle identifier and iCloud container in the project settings and `PlayCount/PlayCount.entitlements`.

`main` is the forward-development branch. It keeps the iOS 27 App Intents, Siri relevance, and Icon Composer features while using availability checks for runtime behavior that requires iOS 27.

## Repository layout

- `PlayCount/` — app source, assets, entitlements, and the layered Icon Composer package
- `PlayCountTests/` — recap, sync, App Intent, and performance-oriented regression tests
- `PlayCountUITests/` — focused navigation and diagnostics UI coverage
- `docs/` — API constraints and release architecture notes

Generated screenshots, visual-audit captures, local Icon Composer experiments, archives, and Xcode user state are intentionally excluded from source control.
