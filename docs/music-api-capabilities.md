# PlayCount Music API Capabilities

This note maps the Apple music APIs relevant to PlayCount, based on the app's current code and Apple Developer documentation checked on 2026-05-04.

## Current app usage

PlayCount currently uses `MediaPlayer`, not MusicKit.

- `PlayCount/MediaLibraryManager.swift` imports `MediaPlayer`.
- The app reads local library items with `MPMediaQuery.songs()`, `MPMediaQuery.albums()`, and `MPMediaQuery.artists()`.
- The app reads item metadata from `MPMediaItem`, including `persistentID`, `title`, `artist`, `albumTitle`, `playCount`, `playbackDuration`, `lastPlayedDate`, `artwork`, album IDs, artist IDs, disc number, and track number.
- The app controls playback through `MPMusicPlayerController.systemMusicPlayer`.
- The app requests media library access with `MPMediaLibrary.authorizationStatus()` and `MPMediaLibrary.requestAuthorization`.
- The app has generated Info.plist key `NSAppleMusicUsageDescription`.

## MediaPlayer

### `MPMediaLibrary`

Use this for permission and access to the device's synced media library.

Useful capabilities:

- Check access with `authorizationStatus()`.
- Request access with `requestAuthorization`.
- Use `default()` for the device's default media library.
- Observe library changes with `beginGeneratingLibraryChangeNotifications()` and `endGeneratingLibraryChangeNotifications()`.
- Read `lastModifiedDate`.
- Add Apple Music catalog items to the user's library with `addItem(withProductID:)`.
- Retrieve or create app-maintained playlists with `getPlaylist(with:creationMetadata:completionHandler:)`.

Fit for PlayCount:

- Keep using this for the app's core local-library ranking model.
- Add library-change notifications so rankings refresh after sync/library changes.
- It does not provide a complete historical playback event stream, so it cannot directly produce accurate "plays this month" if the app did not previously snapshot counts.

Source: https://developer.apple.com/documentation/mediaplayer/mpmedialibrary

### `MPMediaQuery`

Use this to retrieve local media items and collections.

Useful capabilities:

- Query the full library, or apply `MPMediaPropertyPredicate` filters.
- Group results by songs, albums, artists, playlists, composers, genres, and related media groupings through convenience queries.
- Retrieve raw `items`, grouped `collections`, and UI-friendly sections.
- Filter by persistent IDs for playback/detail flows.

Fit for PlayCount:

- Best source for top songs, albums, and artists already in the user's local library.
- Good for local search, detail pages, and playback queues.
- Monthly recaps can use `lastPlayedDate` as a weak proxy for recently played content, but play counts are cumulative totals, not period-bounded counts.

Source: https://developer.apple.com/documentation/mediaplayer/mpmediaquery

### `MPMediaItem`

Use this for metadata and library stats for a single media item.

Useful capabilities:

- Stable local identifiers: `persistentID`, `albumPersistentID`, `artistPersistentID`, `genrePersistentID`, `composerPersistentID`.
- Display metadata: `title`, `artist`, `albumArtist`, `albumTitle`, `genre`, `composer`, `lyrics`, `releaseDate`, `artwork`.
- Listening-related metadata: `playCount`, `skipCount`, `lastPlayedDate`, `playbackDuration`, `dateAdded`, `rating`.
- Catalog bridge: `playbackStoreID` can identify the Apple Music catalog item.
- Library state: `isCloudItem`, `hasProtectedAsset`, `assetURL`.

Fit for PlayCount:

- Current ranking by play count and estimated listening time is appropriate: `totalPlayDuration = playCount * playbackDuration`.
- Recaps based only on `MPMediaItem` are limited to cumulative totals and the most recent play date. There is no per-play timestamp list.
- `skipCount`, `dateAdded`, `genre`, `releaseDate`, `rating`, and `playbackStoreID` open up useful feature surfaces without adopting MusicKit.

Source: https://developer.apple.com/documentation/mediaplayer/mpmediaitem

### `MPMediaItemCollection`

Use this to represent a playable or grouped set of local media items.

Useful capabilities:

- Build collections from query results or sorted item arrays.
- Use collections as playback queues.
- Read `representativeItem` and `items` for album/artist aggregation.

Fit for PlayCount:

- Already a good fit for album and artist play buttons.
- Can support recap playlists if paired with `MPMediaLibrary` playlist creation.

Source: https://developer.apple.com/documentation/mediaplayer/mpmediaitemcollection

### `MPMusicPlayerController`

Use this to play local library and Apple Music items.

Useful capabilities:

- `systemMusicPlayer` controls the Music app's playback state.
- `applicationMusicPlayer` and `applicationQueuePlayer` play within the app; the queue player gives more queue control.
- Set queues with `MPMediaQuery`, `MPMediaItemCollection`, store identifiers, or queue descriptors.
- Control playback with play, pause, skip, repeat, shuffle, and now-playing item APIs.
- Subscribe to now-playing and playback-state notifications.

Fit for PlayCount:

- Current `systemMusicPlayer` choice is appropriate for a companion app that reflects and controls Music.app.
- For a more self-contained player experience, consider `applicationQueuePlayer`, but that changes user expectations because it does not mirror Music.app in the same way.
- Playback notifications are useful for now-playing UI, but they do not replace library-change notifications for refreshing rankings.

Source: https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller

## MusicKit for Swift

MusicKit is not currently used by PlayCount. It is the likely next layer if the app needs Apple Music catalog enrichment, richer search, Apple Music account features, or Swift-native playback APIs.

### `MusicAuthorization`

Use this to request permission for MusicKit access.

Useful capabilities:

- Check `MusicAuthorization.currentStatus`.
- Request permission with `MusicAuthorization.request()`.

Fit for PlayCount:

- Needed before fetching user-specific Apple Music data through MusicKit.
- This is separate from the app's current `MPMediaLibraryAuthorizationStatus` model, so the UI should treat MediaPlayer access and MusicKit access as related but distinct permission states.

Source: https://developer.apple.com/documentation/musickit/musicauthorization

### `MusicLibraryRequest`

Use this to fetch the user's Apple Music library with Swift-native MusicKit models.

Useful capabilities:

- Fetch user-library albums, artists, songs, playlists, genres, music videos, playlist entries, and tracks when the item type conforms to `MusicLibraryRequestable`.
- Apply supported library filters and sort properties.

Fit for PlayCount:

- Useful if PlayCount wants a MusicKit-native library layer or playlist features.
- Need to verify available item properties before replacing `MPMediaItem`; MusicKit library data is cleaner for Apple Music integration but may not expose the same local-library play-count fields that PlayCount depends on.

Sources:

- https://developer.apple.com/documentation/musickit/musiclibraryrequest
- https://developer.apple.com/documentation/musickit/musiclibraryrequestable

### `MusicCatalogResourceRequest` and `MusicCatalogSearchRequest`

Use these to fetch Apple Music catalog data.

Useful capabilities:

- Fetch catalog songs, albums, artists, playlists, stations, curators, record labels, music videos, and radio shows.
- Search the Apple Music catalog by term.
- Fetch additional async properties for richer detail views.

Fit for PlayCount:

- Enrich local library rows with catalog artwork, editorial notes, genres, release dates, URLs, and related catalog entities.
- Use `MPMediaItem.playbackStoreID` as a bridge when available.
- This is not the primary source for personal play counts.

Sources:

- https://developer.apple.com/documentation/musickit/musiccatalogresourcerequest
- https://developer.apple.com/documentation/musickit/musiccatalogsearchrequest

### `SystemMusicPlayer` and `ApplicationMusicPlayer`

Use these as Swift-native MusicKit playback APIs.

Useful capabilities:

- `SystemMusicPlayer.shared` controls Music.app state.
- `ApplicationMusicPlayer.shared` plays in the app without affecting Music.app state.
- Common `MusicPlayer` APIs expose queue, playback time, state, play, pause, skip, seek, stop, repeat, and shuffle controls.

Fit for PlayCount:

- `SystemMusicPlayer` is the MusicKit equivalent of the app's current system-player model.
- `ApplicationMusicPlayer` could support a more app-owned listening experience, but it would be a product shift.
- Migration is optional unless MusicKit models or Apple Music account features become central.

Sources:

- https://developer.apple.com/documentation/musickit/systemmusicplayer
- https://developer.apple.com/documentation/musickit/applicationmusicplayer
- https://developer.apple.com/documentation/musickit/musicplayer

## Apple Music API

The Apple Music API is the web-service layer behind catalog and user-specific Apple Music data. On Apple platforms, MusicKit can automatically manage the music user token for user-data requests.

Useful capabilities:

- Retrieve Apple Music catalog resources and user library resources.
- Fetch recommendations, charts, ratings, playlists, stations, and recently played content.
- Create or modify playlists and apply ratings with proper authorization.
- Fetch recent history endpoints, including heavy rotation content, recently played resources, recently played tracks, recently played stations, and recently added resources.

Fit for PlayCount:

- This is the strongest candidate for "recap-like" recent Apple Music history if local `MPMediaItem` data is not enough.
- Recently played endpoints are recent-history APIs, not full historical analytics. They should be treated as a supplement, not a complete monthly archive.
- Requires Apple Music user authorization and token handling. On Apple platforms, prefer MusicKit first unless a REST-only endpoint is needed.

Sources:

- https://developer.apple.com/documentation/applemusicapi/
- https://developer.apple.com/documentation/applemusicapi/history
- https://developer.apple.com/documentation/applemusicapi/get-recently-played-resources
- https://developer.apple.com/documentation/applemusicapi/user_authentication_for_musickit

## Monthly recap implications

### What can be done with current MediaPlayer data

Possible without a new API layer:

- All-time top songs, albums, and artists.
- Estimated all-time listening time.
- Recently played list from items where `lastPlayedDate` is present.
- Recently active artists/albums by grouping songs with recent `lastPlayedDate`.
- Newly added music from `dateAdded`.
- Genre, decade, explicit, skip-count, and rating-based summaries.

Limitations:

- No complete per-play history.
- No built-in monthly play deltas.
- `lastPlayedDate` only records the latest play, not every play.
- `playCount` is cumulative, so a song with 100 lifetime plays and one play this month still looks like 100 plays.

### What needs local snapshotting

For accurate monthly recaps, PlayCount should persist periodic snapshots:

- Song persistent ID.
- Play count.
- Skip count.
- Last played date.
- Playback duration.
- Album and artist persistent IDs.
- Optional metadata copy for stable recap rendering if the library changes later.

Then monthly deltas can be calculated as:

- Monthly plays = current `playCount` - prior snapshot `playCount`.
- Monthly estimated listening time = play delta * `playbackDuration`.
- Monthly skips = current `skipCount` - prior snapshot `skipCount`.
- Monthly new additions = `dateAdded` inside the month.

This is the most reliable path for PlayCount because it preserves the app's local-library orientation and works for imported or purchased music that may not exist cleanly in the Apple Music catalog.

### Where Apple Music recent history helps

MusicKit or Apple Music API recent-history endpoints can supplement recaps with:

- Recently played Apple Music resources.
- Heavy rotation.
- Recently added library resources.
- Better catalog artwork and metadata.

This should not be the only recap data source unless the product intentionally becomes Apple Music account-centric rather than local-library-centric.

## Liquid Glass implications

Liquid Glass is a UI layer, not a music-data API. Apple's SwiftUI APIs include:

- `glassEffect(_:in:)` for applying Liquid Glass to custom views.
- `Glass` configuration with tinting and interactivity.
- `GlassEffectContainer` for combining multiple glass shapes and enabling better rendering/morphing behavior.
- Glass button styles for standard controls.

Good PlayCount candidates:

- Now Playing bar surface.
- Playback buttons.
- Sort segmented/menu controls.
- Recap month picker and summary chips.
- Floating search/filter affordances.

Implementation guidance:

- Build with current Xcode/iOS SDK first; standard SwiftUI controls may adopt Liquid Glass automatically.
- Use custom glass sparingly on high-value surfaces.
- Gate custom Liquid Glass code with `#available(iOS 26, *)` and keep existing material/background fallbacks for earlier OS versions.
- Use `GlassEffectContainer` when multiple glass controls live in the same cluster.
- Use interactive glass only for tappable controls.

Sources:

- https://developer.apple.com/documentation/TechnologyOverviews/liquid-glass
- https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29
- https://developer.apple.com/documentation/swiftui/glass
- https://developer.apple.com/documentation/swiftui/glasseffectcontainer

## Recommended feature direction

1. Add a small persistence layer for monthly snapshots before building recap UI.
2. Listen for library-change notifications and refresh snapshots opportunistically.
3. Keep MediaPlayer as the source of truth for local play counts.
4. Add MusicKit only if the feature needs catalog enrichment, Apple Music account history, playlist creation, or richer Apple Music search.
5. Build the recap UI with existing SwiftUI first, then add iOS 26 Liquid Glass accents around the Now Playing bar, controls, and recap summary chips.
