# iOS 26 release and iOS 27 handoff

PlayCount keeps the public App Store release and the forward-looking iOS 27
integration on separate branches because App Store Connect currently rejects
archives built with beta versions of Xcode.

## Branch roles

- `main` is the forward branch. It retains the iOS 27 audio entity schemas,
  now-playing relevance donation, view entity identifiers, execution targets,
  and the Generation 27 Icon Composer refraction/specular configuration.
- `codex/ios26-release` is the public 4.0 release branch. It is built with
  Xcode 26.6 and contains the same product, recap, reliability, performance,
  design, Spotlight, and existing App Intent functionality without APIs that
  are absent from the iOS 26 SDK.

Do not merge the iOS 26 compatibility-removal commit back into `main`. Product
fixes made after this split should be applied to both branches when relevant.

## iOS 27 layer retained on `main`

The forward-only implementation is concentrated in:

- `PlayCount/PlayCountAppIntents.swift`
- `PlayCount/PlayCountSiriIntegration.swift`
- `PlayCount/MediaLibraryManager.swift`
- `PlayCount/SystemIntegrationView.swift`
- `PlayCountTests/PlayCountAppIntentTests.swift`
- `PlayCount/PlayCountIcon.icon/icon.json`

The iOS 26 release keeps the layered `.icon` package and its Default, Dark,
and Tinted appearance specializations. It removes only Generation 27
`refractivity` and explicit specular-location fields; it does not replace the
icon with a raster export.

## Future release procedure

When a public Xcode 27 release is accepted by App Store Connect:

1. Start from `main`, not `codex/ios26-release`.
2. Merge or cherry-pick any later product fixes from the release branch without
   taking its SDK-27 removal commit.
3. Build the app and tests with the public Xcode 27 toolchain.
4. Verify the app icon in Default, Dark, and Tinted modes at full size and on a
   device.
5. Verify Siri/App Intents metadata extraction, audio entity resolution,
   Spotlight indexing, and now-playing relevance donation.
6. Archive and upload a new build, then treat upload, processing, TestFlight,
   and App Review eligibility as separate proof steps.
