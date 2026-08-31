# Startup reliability audit

Date: 2026-08-31. Base: `6cfd8d1` (4.0.2 build 11). Branch: `codex/startup-reliability`.

## Scope and evidence

A customer reported waiting at “Getting your library ready” followed by termination. No customer crash, watchdog, or Jetsam report was available. The following are verified source-level risks and regression-tested fixes, not proof of that customer's exact termination cause.

| Risk | Change | Regression evidence |
| --- | --- | --- |
| Cached library publication waited for the recap store's serial queue | Publish the library cache independently; restore cached insights asynchronously | Block recap storage and verify both cached and live library publication |
| SwiftUI-facing recap getters could synchronously wait for migration | Serve immutable in-memory presentation caches; refresh/cloud completion seeds history | Call monthly/yearly/highlight getters while the storage queue is blocked |
| Fresh library publication waited for milestone database work | Publish rankings first, persist the next-launch cache, then process milestones/recaps | Block milestone storage and verify visible library plus saved cache |
| Legacy pretty-printed archive reader repeatedly searched the remaining file for its terminator | Locate the terminator once, decode one snapshot at a time inside an autorelease pool | Read all 500 snapshots in both pretty and compact formats |
| Duplicate persisted/native IDs could trigger a fatal dictionary initializer or double-count a song | Deduplicate native IDs before aggregation and use deterministic first-value dictionaries at legacy boundaries | Duplicate native and legacy IDs preserve one recording and the correct next delta |
| Oversized/corrupt presentation JSON could exhaust memory or overflow aggregation | Bound cache reads to 32 MiB; reject invalid numeric data and aggregate overflow | Oversized, malformed, and overflowing caches fail open without deleting history |
| A transient empty Music query discarded useful cached data | Keep last visible library/cache; never feed presentation data back as listening evidence | Empty-query regression retains cache and adds no fabricated recap plays |
| Late asynchronous completion after permission loss could republish data | Generation/token/authorization checks, with clean restart after reauthorization | Revoke access during a blocked read and verify no late publication |
| Full-library temporary allocations and optional indexing overlapped startup | Per-item autorelease pools, worker-side alias indexes, later system observation and Spotlight refresh | 20,000-song cache stress and responsive startup UI tests |

## Preserved behavior

- Rankings, sorting, detail navigation, artwork loading, recap accounting, milestones, CloudKit, and Siri/Spotlight integration remain available.
- Cached metadata is presentation only, not evidence for historical play gains.
- Recap migration verification, archive quarantine/retirement, and offline/partial-library safety policy are unchanged.
- History is not reset or deleted to make startup faster. A fresh library cache is saved before long insight processing so subsequent launches can recover quickly.
- DEBUG-only UI fixtures use an injected delayed library reader and isolated temporary stores, with no real Music, CloudKit, background notification, or Spotlight changes.

## Validation

Use Xcode 26.6 explicitly. Simulator target: iPhone 17 Pro / iOS 26.5.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
  -project PlayCount.xcodeproj -scheme PlayCount \
  -destination 'platform=iOS Simulator,id=6616A56F-21D3-4FD2-962A-3C5410662BF5' \
  -derivedDataPath /tmp/PlayCountStartupTests \
  -parallel-testing-enabled NO -only-testing:PlayCountTests
```

The startup UI suite is `PlayCountUITests/StartupResponsivenessUITests`; it exercises the normal ContentView startup, not screenshot-mode bypass. It captures both UI hierarchies and screenshots. Release verification uses `build -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`.

Final unit run: **212 tests passed**, including all recap accuracy/migration, Cloud sync, milestone, and startup regressions. The 20,000-song cached-library fixture became usable in **0.538 s** while its live scan was deliberately blocked. The 500-snapshot pretty archive (17,046,724 bytes) was read in **0.194 s**. These are simulator fixture timings, not a measured before/after customer-device speedup or memory benchmark.

Final unsigned iOS Release build passed with Xcode 26.6; only the three existing CloudKit deprecation warnings remain. The Release binary contains none of the startup-verification fixture strings.

Final combined result: **216 passed, 0 failed, 0 skipped** (212 unit + 4 startup UI tests). With the injected reader delayed for 12 seconds, saved rankings remained scrollable, song detail opened, Library/Recap tab round-trips finished before live data arrived, and uncached startup stayed navigable before showing the live library. Exact row counts distinguish cached from live content. Screenshots and hierarchies were inspected, not just app liveness.

Artifacts (local, not committed): `/tmp/PlayCountStartupFinal.xcresult`, `/tmp/PlayCountStartupFinal-attachments`, `/tmp/playcount-startup-final-tests.log`, and `/tmp/playcount-startup-release-final.log`.

Review follow-through: kept the original sorted input for deferred Spotlight/shortcut indexing; preserved the catalog identity in cached song metadata with backward-compatible optional decoding; removed duplicate detail notifications. Two prior assertions were updated without weakening accuracy coverage: view getters now require asynchronously seeded presentation data, and a partial policy-3 Cloud manifest cannot downgrade the source archive's current policy. The UI scroll check now asserts an actually visible row and its exact cached count instead of assuming a fixed scroll distance.

## Remaining proof boundary

Simulator/injected-reader coverage does not reproduce Apple Music IPC, real artwork memory, device thermal pressure, or the customer's persisted archive. A framework library query has no cancellation API here; it remains off the main thread and coalesced, but an uncached library still requires that query to finish. Obtain the customer's iPhone model, iOS/app version, and matching crash/Jetsam report to confirm the actual termination class. Do not recommend deleting/reinstalling the app because local recap history may be lost.

This branch does not change version/build numbers, signing, icons, or App Store state. A successful unsigned Release build is not an uploaded or shipped fix.
