# Chronos — marketing assets

## App icon (`AppIcon.svg`)

A clean starting-point icon: a "time block" arc on a clock, in the app's
blue→indigo. Full-bleed (Apple applies the rounded-corner mask itself).

**Export to the 1024×1024 PNG the App Store needs** (pick one):

- **Preview / any browser:** open the SVG, or use an online "SVG to PNG" at
  1024×1024.
- **Command line (if you have `rsvg-convert`):**
  `rsvg-convert -w 1024 -h 1024 AppIcon.svg -o AppIcon-1024.png`
- **Or `cairosvg`:** `cairosvg AppIcon.svg -W 1024 -H 1024 -o AppIcon-1024.png`
- **Design tools:** import the SVG into Figma/Sketch/Affinity, tweak if you like,
  export 1024×1024 PNG.

**Icon rules:** 1024×1024, PNG, **no transparency**, **no rounded corners** (the
art fills the whole square; Apple rounds it), sRGB. Drop it into Xcode's asset
catalog → **AppIcon** (Xcode 15+ accepts the single 1024 and generates the rest).

Treat this as a tasteful default — feel free to refine the mark, or commission a
designer later; swapping the icon is a normal app update.

## Screenshots & App Preview video
See `../SCREENSHOTS_AND_PREVIEW.md` for the exact shot list, captions, sizes, and
the video storyboard.

## Store copy
See `../APP_STORE_LISTING.md` for the name, subtitle, description, keywords, review
notes, and privacy answers — copy-paste ready.
