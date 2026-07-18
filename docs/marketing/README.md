# Chronos — marketing assets

## App icon

The Chronos mark: a single rounded **time block** on a faint hour grid, crossed
by a thin coral **"now" line** anchored by a node — the essence of timeblocking
(a slot of your day, and the moment you're living right now) in one confident
shape, in the app's indigo on premium charcoal.

Two forms, both kept in sync:

- **`AppIcon-1024.png`** — the ready-to-ship 1024×1024 PNG the App Store needs.
  Generated straight from the app's own icon renderer, so it is pixel-identical
  to what ships on the Home Screen.
- **`AppIcon.svg`** — a vector twin, for tweaking in Figma/Sketch/Affinity or
  re-exporting at any size.

**Regenerate everything** (the full iOS + macOS icon set *and* this marketing
PNG) with one command — no design tool required:

```
python3 scripts/make_icon.py
```

That writes the light / dark / tinted iOS 1024s and every macOS size into
`Chronos/Assets.xcassets/AppIcon.appiconset`, plus `AppIcon-1024.png` here.

**Icon rules (already satisfied by the PNG):** 1024×1024, PNG, **no
transparency**, **no rounded corners** (the art fills the whole square; Apple
rounds it), sRGB. In Xcode the asset catalog → **AppIcon** already points at the
generated set, so a fresh `make_icon.py` run is all it takes to update the app.

## Screenshots & App Preview video
See `../SCREENSHOTS_AND_PREVIEW.md` for the exact shot list, captions, sizes, and
the video storyboard.

## Store copy
See `../APP_STORE_LISTING.md` for the name, subtitle, description, keywords, review
notes, and privacy answers — copy-paste ready.
