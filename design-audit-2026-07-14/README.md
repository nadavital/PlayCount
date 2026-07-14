# PlayCount design audit — July 14, 2026

## Scope and evidence

This audit covers the current local PlayCount checkout rendered with deterministic mock-library data on an iPhone 17 Pro and iPad Pro 11-inch simulator. It includes the all-time ranking views, search, recap, artist detail, song detail, dark appearance, Accessibility Large Dynamic Type, and iPad adaptation. It is a design audit of the current checkout, not proof of the exact TestFlight binary.

## Overall assessment

PlayCount has a strong visual foundation. The all-time rankings are unusually coherent for a data-heavy music app, the artwork carries the experience well, and the iPad layout is a genuine recomposition rather than an enlarged phone screen. The biggest weaknesses are accessibility scaling, vertical-space efficiency, the mismatch between song and artist/album detail structures, low-contrast secondary information, and a recap navigation model that visually suggests gesture competition.

## Flow review

1. **Top Songs, Albums, and Artists — healthy.** These three views share the same large title, ranking card, medal system, artwork scale, trailing metric, toolbar controls, now-playing accessory, and tab treatment. This is the strongest consistency seam in the app.
2. **Search — functional but visually disconnected.** Results reuse the ranking-row language, but the inline title, oversized category container, bottom search field, and large empty gaps create a different rhythm from the three primary library views.
3. **Monthly Recap — distinctive but crowded.** The artwork-led hero gives recap a clear identity and the summary hierarchy is understandable. On iPhone, the hero, title, horizontal month rail, summary card, now-playing bar, and tab bar compete for the same viewport; very little analysis is visible before scrolling.
4. **Artist detail — directionally strong.** The compact split header keeps top songs visible and the toolbar metric control matches the library pages. The derived background color makes the page feel connected to the artwork.
5. **Song detail — polished but oversized and inconsistent.** The artwork dominates the viewport, followed by a large metadata card and two statistic cards. Compared with artist detail, it delays useful information and establishes a second detail-page grammar.
6. **Dark appearance — generally healthy.** Surfaces and artwork transition cleanly and the hierarchy survives. Secondary text becomes too dim, especially duration and tertiary metadata.
7. **Accessibility Large Dynamic Type — unhealthy.** Core song, artist, album, duration, and detail-header labels truncate to fragments. The layout technically scales text, but fixed horizontal allocations do not reflow around it.
8. **iPad — healthy with minor density issues.** The dashboard and two-column recap use width effectively and preserve the phone design language. The bottom now-playing accessory still visually overlaps the final content rows.

## Findings by priority

### P1 — Fix before broader visual polish

1. **Make ranking rows and detail headers reflow for accessibility text sizes.** At Accessibility Large, titles become fragments such as “Afte…” and “Velv…”, artist names and listening-time labels truncate, and the artist summary card loses context. Switch to an accessibility layout that moves the metric below the title, permits two lines for identity text, hides or relocates chevrons, and reduces artwork/rank size only as a last resort.
2. **Guarantee content clearance above persistent bottom chrome.** The now-playing accessory plus tab bar obscures or visually washes out the final rows on phone and iPad, most noticeably in recap. Apply a shared bottom content inset/safe-area strategy to every scroll container and verify the last interactive element can scroll fully above both layers.
3. **Reduce the recap phone header footprint.** The initial recap viewport spends roughly half its height on artwork and month navigation before the analytical content begins. Use a shorter hero on compact width, or collapse it after the first scroll, and keep the selected month/year in a compact sticky control.
4. **Unify song, album, and artist detail scaffolds.** Artist detail now has the better compact pattern. Reuse a shared responsive detail header, consistent toolbar metric control, playback placement, card padding, and background treatment. Song artwork should be bounded by viewport height so metadata and at least one useful secondary section appear above the fold.

### P2 — High-value consistency improvements

5. **Make the metric control self-explanatory.** A bare “#” is compact but cryptic. Pair the icon with the current state (“Plays” or “Time”), or use a compact menu/segmented control whose selected metric is readable without experimentation. Keep the same control on library and detail views.
6. **Simplify recap month navigation.** The horizontal chip rail clips the selected July chip at the trailing edge on iPhone and competes with page-like horizontal gestures. Prefer a centered previous/current/next month control, a month picker sheet, or snapping pages with a clearly reserved swipe region. Avoid nesting tap targets inside the gesture surface used for month changes.
7. **Bring Search into the main-page rhythm.** Use the same large-title hierarchy or deliberately adopt a compact search-specific header, but remove the oversized white shell around the segmented picker and reduce the blank vertical intervals. A search scope menu in the search field or a compact pinned segment would expose more results.
8. **Increase secondary-text contrast.** Duration, rank context, and some recap annotations are faint in light appearance and become especially weak in dark appearance or on artwork-derived backgrounds. Promote essential secondary text to `secondary`, reserve `tertiary` styling for nonessential metadata, and add a contrast-preserving overlay/token for derived-color detail pages.
9. **Standardize card tokens.** Main rankings, recap, detail summaries, and iPad panels use related but not identical corner radii, fills, borders, and padding. Define a small token set—for example list container, summary card, and hero card—so special screens feel expressive without appearing to belong to another app.

### P3 — Polish

10. **Clarify tap affordances.** Main rows use chevrons, recap cards generally do not, and the large “Most Played” card can read as informational rather than navigable. Use a consistent content-link affordance or pressed state for every tappable media card.
11. **Reduce repeated identity.** Detail pages repeat the item name in the navigation title and again inside the header card. Let the title transition from the hero into the navigation bar on scroll rather than showing both simultaneously.
12. **Tune iPad density and balance.** The iPad dashboard is effective, but the two ranking columns are long and visually dominant. Consider a third artists column at wider widths or a configurable section layout, while preserving the strong summary strip.

## Strengths worth preserving

- The shared Songs/Albums/Artists ranking grammar is clear and immediately learnable.
- Artwork is used as data identity rather than decoration, and scales well across phone and iPad.
- Medal ranks give the top three meaningful emphasis without overwhelming later entries.
- The now-playing accessory is visually integrated and consistent across main surfaces.
- Recap feels like a special event without losing the underlying media identity.
- The iPad dashboard and recap both make intentional use of width.

## Accessibility risks and evidence limits

- Dynamic Type at Accessibility Large produced severe truncation on the ranking and artist-detail screens.
- Several essential secondary labels appear low contrast in both light and dark appearance; exact contrast ratios were not measured in this pass.
- Screenshots cannot prove VoiceOver order, accessibility labels, Switch Control behavior, hit-target size, Reduce Motion handling, or the reported recap swipe-versus-tap conflict. Those require a separate interaction/accessibility test pass.
- The first iPad capture was discarded because it caught an app transition; the retained iPad screenshots were recaptured after the UI settled.

