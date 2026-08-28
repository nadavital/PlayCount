# Release and iOS 27 development

PlayCount 4.0 was released from the Xcode 26-compatible source preserved by the
`v4.0` tag. The forward-looking iOS 27 implementation lives on `main`.

## Main branch

`main` retains the iOS 27 audio entity schemas, now-playing relevance donation,
view entity identifiers, intent execution targets, and Generation 27 Icon
Composer refraction and specular configuration. Runtime-only iOS 27 behavior is
guarded with availability checks, while compiling the branch requires the iOS
27 SDK.

The forward-only implementation is concentrated in:

- `PlayCount/PlayCountAppIntents.swift`
- `PlayCount/PlayCountSiriIntegration.swift`
- `PlayCount/MediaLibraryManager.swift`
- `PlayCount/SystemIntegrationView.swift`
- `PlayCountTests/PlayCountAppIntentTests.swift`
- `PlayCount/PlayCountIcon.icon/icon.json`

## Public 4.0 source

The `v4.0` tag points to the exact Xcode 26-compatible source used for the
public 4.0 release. That source keeps the layered `.icon` package and its
Default, Dark, and Tinted appearance specializations while omitting only SDK 27
APIs and Generation 27-only Icon Composer fields.

Do not merge the historical SDK-27 removal commit into `main`. Product fixes
from the release line have already been applied separately so the forward
branch retains both the public release fixes and the iOS 27 layer.

## Release verification

For a future release from `main`:

1. Build and test with the current public Xcode toolchain.
2. Verify the app icon in Default, Dark, and Tinted modes at full size and on a device.
3. Verify Siri/App Intents metadata extraction, entity resolution, Spotlight indexing, and now-playing relevance donation.
4. Archive and upload a new build.
5. Treat archive success, upload, processing, TestFlight availability, and App Review status as separate proof steps.
