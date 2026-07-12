#!/usr/bin/env python3
"""Generates the Chronos app icon set.

The mark: a single rounded "time block" sitting on a faint hour-grid, with a
thin accent "now" line crossing it — the essence of timeblocking, reduced to
one confident shape. Rendered at 4x then downsampled for crisp antialiasing.
Produces the iOS single 1024 (light / dark / tinted appearances) and every
macOS size.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "Chronos", "Assets.xcassets", "AppIcon.appiconset")
SS = 4  # supersample

INDIGO = (124, 140, 248)
INDIGO_DEEP = (92, 108, 220)
BG_TOP = (24, 26, 34)
BG_BOT = (11, 12, 15)
INK = (242, 243, 245)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rounded(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def render(size, style="light", rounded_bg=False):
    """style: light | dark | tinted. rounded_bg rounds the icon itself (macOS)."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Background (iOS masks to squircle itself; macOS wants a rounded tile).
    if style == "tinted":
        # Grayscale source; system applies the tint. Dark base + light marks.
        bg_top, bg_bot = (30, 30, 30), (10, 10, 10)
        block_col = (150, 150, 150)
        block_top = (200, 200, 200)
        grid_col = (255, 255, 255, 26)
        now_col = (235, 235, 235)
    else:
        bg_top, bg_bot = BG_TOP, BG_BOT
        block_col = INDIGO_DEEP
        block_top = INDIGO
        grid_col = (255, 255, 255, 22)
        now_col = (255, 93, 93)

    # Vertical gradient background.
    for y in range(s):
        t = y / s
        d.line([(0, y), (s, y)], fill=lerp(bg_top, bg_bot, t))

    if rounded_bg:
        # Mask corners for macOS tile.
        mask = Image.new("L", (s, s), 0)
        md = ImageDraw.Draw(mask)
        md.rounded_rectangle([0, 0, s, s], radius=int(s * 0.185), fill=255)
        img.putalpha(mask)
        d = ImageDraw.Draw(img)

    # Hour grid — faint horizontal hairlines.
    grid = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    margin = s * 0.30
    for i in range(1, 6):
        y = margin + (s - 2 * margin) * i / 6
        gd.line([(s * 0.24, y), (s * 0.76, y)], fill=grid_col, width=max(1, int(s * 0.004)))
    img.alpha_composite(grid)
    d = ImageDraw.Draw(img)

    # The time block — a bold rounded vertical bar, slightly gradient.
    bx0, bx1 = s * 0.40, s * 0.60
    by0, by1 = s * 0.26, s * 0.74
    r = int((bx1 - bx0) * 0.42)
    # Soft drop shadow.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = int(s * 0.02)
    sd.rounded_rectangle([bx0, by0 + off, bx1, by1 + off], radius=r, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=s * 0.02))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)

    # Block body with a top-to-bottom accent gradient.
    block = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    bd = ImageDraw.Draw(block)
    bd.rounded_rectangle([bx0, by0, bx1, by1], radius=r, fill=block_col)
    # gradient overlay
    grad = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    grd = ImageDraw.Draw(grad)
    for y in range(int(by0), int(by1)):
        t = (y - by0) / (by1 - by0)
        grd.line([(bx0, y), (bx1, y)], fill=lerp(block_top, block_col, t) + (255,))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle([bx0, by0, bx1, by1], radius=r, fill=255)
    block.paste(grad, (0, 0), mask)
    img.alpha_composite(block)
    d = ImageDraw.Draw(img)

    # The "now" line — thin accent crossing the block.
    ny = s * 0.545
    lw = max(2, int(s * 0.012))
    d.line([(s * 0.24, ny), (s * 0.76, ny)], fill=now_col, width=lw)
    dot_r = int(s * 0.022)
    d.ellipse([s * 0.24 - dot_r, ny - dot_r, s * 0.24 + dot_r, ny + dot_r], fill=now_col)

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
    mac_sizes = [16, 32, 64, 128, 256, 512, 1024]
    for px in mac_sizes:
        save(render(px, "light", rounded_bg=True), f"icon-mac-{px}.png")

    print("Icons written to", os.path.relpath(OUT))


if __name__ == "__main__":
    main()
