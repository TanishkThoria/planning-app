#!/usr/bin/env python3
"""Generates the Chronos app icon set.

The mark: a single confident "time block" — a rounded event card sitting on a
faint hour grid — with a thin coral "now" line crossing it and anchored by a
node on the left. It's the essence of timeblocking reduced to one shape: a slot
of your day, and the moment you're living right now. Rendered at 4x then
downsampled for crisp antialiasing. Produces the iOS single 1024 (light / dark
/ tinted appearances) and every macOS size.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "Chronos", "Assets.xcassets", "AppIcon.appiconset")
SS = 4  # supersample

INDIGO = (129, 145, 255)       # block top — brighter, more saturated for punch
INDIGO_DEEP = (98, 112, 226)   # block bottom
BG_TOP = (26, 28, 38)          # faint indigo-tinted charcoal
BG_BOT = (12, 13, 18)
CORAL = (255, 96, 92)          # the "now" line


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def render(size, style="light", rounded_bg=False):
    """style: light | dark | tinted. rounded_bg rounds the icon itself (macOS)."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if style == "tinted":
        # Grayscale source; the system applies the user's tint. Dark base, light marks.
        bg_top, bg_bot = (28, 28, 28), (9, 9, 9)
        block_col, block_top = (150, 150, 150), (205, 205, 205)
        grid_col = (255, 255, 255, 24)
        now_col = (236, 236, 236)
        content_col = (30, 30, 30, 150)
    elif style == "dark":
        bg_top, bg_bot = (20, 21, 28), (8, 8, 11)
        block_col, block_top = INDIGO_DEEP, INDIGO
        grid_col = (255, 255, 255, 20)
        now_col = CORAL
        content_col = (255, 255, 255, 165)
    else:  # light (the primary, premium dark-background mark)
        bg_top, bg_bot = BG_TOP, BG_BOT
        block_col, block_top = INDIGO_DEEP, INDIGO
        grid_col = (255, 255, 255, 24)
        now_col = CORAL
        content_col = (255, 255, 255, 170)

    # Vertical gradient background.
    for y in range(s):
        d.line([(0, y), (s, y)], fill=lerp(bg_top, bg_bot, y / s))

    if rounded_bg:
        # Mask corners for the macOS tile (iOS masks to the squircle itself).
        mask = Image.new("L", (s, s), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, s, s], radius=int(s * 0.185), fill=255)
        img.putalpha(mask)
        d = ImageDraw.Draw(img)

    # Hour grid — faint horizontal hairlines spanning the full width so the block
    # clearly sits *inside* a day column.
    grid = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    gx0, gx1 = s * 0.16, s * 0.84
    top, bot = s * 0.20, s * 0.80
    for i in range(6):
        y = top + (bot - top) * i / 5
        gd.line([(gx0, y), (gx1, y)], fill=grid_col, width=max(1, int(s * 0.0035)))
    img.alpha_composite(grid)
    d = ImageDraw.Draw(img)

    # The time block — a bold rounded event card (wider than a pill so it reads
    # unmistakably as a scheduled block, not a bar).
    bx0, bx1 = s * 0.345, s * 0.655
    by0, by1 = s * 0.235, s * 0.765
    r = int((bx1 - bx0) * 0.28)   # rounded-rect corners, not a full capsule

    # Soft drop shadow to lift the block off the grid.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    off = int(s * 0.018)
    ImageDraw.Draw(shadow).rounded_rectangle(
        [bx0, by0 + off, bx1, by1 + off], radius=r, fill=(0, 0, 0, 120))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(radius=s * 0.02)))
    d = ImageDraw.Draw(img)

    # Block body with a top-to-bottom accent gradient.
    grad = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    grd = ImageDraw.Draw(grad)
    for y in range(int(by0), int(by1) + 1):
        t = (y - by0) / (by1 - by0)
        grd.line([(bx0, y), (bx1, y)], fill=lerp(block_top, block_col, t) + (255,))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([bx0, by0, bx1, by1], radius=r, fill=255)
    block = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    block.paste(grad, (0, 0), mask)
    img.alpha_composite(block)
    d = ImageDraw.Draw(img)

    # A crisp top highlight edge for a glassy, premium feel.
    hl = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle(
        [bx0, by0, bx1, by1], radius=r, outline=(255, 255, 255, 46),
        width=max(1, int(s * 0.006)))
    img.alpha_composite(hl)
    d = ImageDraw.Draw(img)

    # Two short "content" hint lines near the top of the card — the way an event
    # shows a title. Small detail that makes the mark read instantly as a block.
    cx0 = bx0 + (bx1 - bx0) * 0.20
    cw_long = (bx1 - bx0) * 0.60
    cw_short = (bx1 - bx0) * 0.38
    ch = max(2, int(s * 0.012))
    cy1 = by0 + (by1 - by0) * 0.20
    cy2 = cy1 + (by1 - by0) * 0.11
    d.rounded_rectangle([cx0, cy1, cx0 + cw_long, cy1 + ch], radius=ch // 2, fill=content_col)
    d.rounded_rectangle([cx0, cy2, cx0 + cw_short, cy2 + ch], radius=ch // 2, fill=content_col)

    # The "now" line — a bold coral rule crossing the whole column, anchored by a
    # filled node on the left. The signature detail; kept thick so it still reads
    # at Dock / small-icon sizes.
    ny = s * 0.560
    lw = max(3, int(s * 0.019))
    nx0, nx1 = s * 0.15, s * 0.85
    d.line([(nx0, ny), (nx1, ny)], fill=now_col, width=lw)
    dot_r = int(s * 0.030)
    d.ellipse([nx0 - dot_r, ny - dot_r, nx0 + dot_r, ny + dot_r], fill=now_col)
    # A faint white core in the node for a little depth.
    core = int(dot_r * 0.34)
    d.ellipse([nx0 - core, ny - core, nx0 + core, ny + core], fill=(255, 255, 255, 210))

    return img.resize((size, size), Image.LANCZOS)


def save(img, name):
    img.save(os.path.join(OUT, name))


def main():
    os.makedirs(OUT, exist_ok=True)

    # iOS universal 1024 — light, dark, tinted.
    save(render(1024, "light"), "icon-ios-1024.png")
    save(render(1024, "dark"), "icon-ios-1024-dark.png")
    save(render(1024, "tinted"), "icon-ios-1024-tinted.png")

    # macOS sizes (rounded tile baked in).
    for px in [16, 32, 64, 128, 256, 512, 1024]:
        save(render(px, "light", rounded_bg=True), f"icon-mac-{px}.png")

    # A flat 1024 for the App Store / marketing (no rounded tile — the store
    # applies its own mask), plus a marketing copy alongside the docs.
    marketing = os.path.join(os.path.dirname(__file__), "..", "docs", "marketing")
    os.makedirs(marketing, exist_ok=True)
    render(1024, "light").save(os.path.join(marketing, "AppIcon-1024.png"))

    print("Icons written to", os.path.relpath(OUT))
    print("Marketing 1024 written to", os.path.relpath(os.path.join(marketing, "AppIcon-1024.png")))


if __name__ == "__main__":
    main()
