# PlayCount Icon Composer explorations

These are selectable design explorations. `PlayCountHaloNote` has been chosen as the current shipping direction; the remaining packages are retained for comparison.

- `PlayCountHaloNote`: centered concentric glass medals with the music-note identity.
- `PlayCountOffsetNote`: offset overlapping discs with the music note; more energetic.
- `PlayCountOffsetPlay`: offset overlapping discs with a play symbol; more direct at small sizes.
- `PlayCountMedalStack`: a simplified wearable medal with layered glass circles; closest to the in-app milestones.

Each package uses four or fewer Icon Composer groups and keeps material, translucency, refraction, and specular effects in Icon Composer rather than baking them into the SVG assets.

The refined `PlayCountHaloNote` treatment is now the selected shipping icon. The raster assets from the previous icon remain preserved in `LegacyPlayCountIconAssets` for exact rollback.
