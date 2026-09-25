#!/usr/bin/env python3
"""Renders calto's app icon into the asset catalog.

Standard library only: shapes are signed-distance functions evaluated per pixel (anti-aliased by
distance), PNGs are written with zlib. Re-run after changing the design:

    python3 scripts/generate-icon.py
"""

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "calto/Resources/Assets.xcassets/AppIcon.appiconset"

# macOS app icon slots: (point size, scale).
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

# Design coordinates are on Apple's 1024 px macOS icon grid (824 px body, 100 px margin).
BODY = (100, 100, 924, 924, 185)
PAGE = (262, 300, 762, 790, 64)
HEADER_BOTTOM = 420
RINGS = [(372, 250, 408, 350, 18), (616, 250, 652, 350, 18)]
GRID_COLUMNS = [362, 462, 562, 662]
GRID_ROWS = [515, 605, 695]
CELL = 62
HIGHLIGHT = (1, 1)  # (row, column) of the "today" cell
SPARKLES = [(745, 745, 170), (850, 540, 58)]


def hex_color(value):
    return tuple(int(value[i:i + 2], 16) / 255 for i in (1, 3, 5))


TOP = hex_color("#5B8DFF")
BOTTOM = hex_color("#6B45E8")
PAGE_COLOR = hex_color("#FFFFFF")
HEADER = hex_color("#FF5B5F")
RING = hex_color("#E9ECF5")
CELL_COLOR = hex_color("#DDE3F4")
CELL_TODAY = hex_color("#4F7BFF")
SPARKLE_INNER = hex_color("#FFE27A")
SPARKLE_OUTER = hex_color("#FFB020")


def rounded_rect(x, y, rect):
    x0, y0, x1, y1, r = rect
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx, qy = abs(x - cx) - hx, abs(y - cy) - hy
    outside = math.hypot(max(qx, 0), max(qy, 0))
    return outside + min(max(qx, qy), 0) - r


def sparkle(x, y, star, power=0.5):
    """Four-point star |x/r|^p + |y/r|^p = 1 (p < 1 makes concave arms; smaller p, thinner arms).
    Distance is approximated as f / |grad f| inside the bounding box and by the nearest tip outside."""
    cx, cy, r = star
    dx, dy = abs(x - cx), abs(y - cy)
    if dx >= r or dy >= r:
        # Outside the bounding box the closest part of the star is one of its tips.
        return min(math.hypot(dx - r, dy), math.hypot(dx, dy - r))
    dx, dy = max(dx, 0.05 * r), max(dy, 0.05 * r)
    u, v = dx / r, dy / r
    f = u ** power + v ** power - 1
    gx, gy = power / r * u ** (power - 1), power / r * v ** (power - 1)
    return f / math.hypot(gx, gy)


def coverage(distance, pixel):
    return min(max(0.5 - distance / pixel, 0.0), 1.0)


def over(dst, color, alpha):
    r, g, b, a = dst
    out_a = alpha + a * (1 - alpha)
    if out_a == 0:
        return (0.0, 0.0, 0.0, 0.0)
    mix = lambda c, d: (c * alpha + d * a * (1 - alpha)) / out_a
    return (mix(color[0], r), mix(color[1], g), mix(color[2], b), out_a)


def shade(x, y, pixel):
    body = coverage(rounded_rect(x, y, BODY), pixel)
    # Soft shadow below the body, as on Apple's icon template.
    shadow = min(max(0.5 - rounded_rect(x, y - 14, BODY) / 28, 0.0), 1.0) * 0.28
    rgba = (0.0, 0.0, 0.0, shadow * (1 - body))
    if body == 0:
        return rgba

    t = (y - BODY[1]) / (BODY[3] - BODY[1])
    background = tuple(TOP[i] + (BOTTOM[i] - TOP[i]) * t for i in range(3))
    rgba = over(rgba, background, body)

    page_distance = rounded_rect(x, y, PAGE)
    page = coverage(page_distance, pixel)
    if page > 0:
        in_header = coverage(y - HEADER_BOTTOM, pixel)
        color = tuple(HEADER[i] * in_header + PAGE_COLOR[i] * (1 - in_header) for i in range(3))
        rgba = over(rgba, color, page)
        for row, cy in enumerate(GRID_ROWS):
            for column, cx in enumerate(GRID_COLUMNS):
                cell = (cx - CELL / 2, cy - CELL / 2, cx + CELL / 2, cy + CELL / 2, 14)
                a = coverage(rounded_rect(x, y, cell), pixel)
                if a > 0:
                    rgba = over(rgba, CELL_TODAY if (row, column) == HIGHLIGHT else CELL_COLOR, a)

    for ring in RINGS:
        a = coverage(rounded_rect(x, y, ring), pixel)
        if a > 0:
            rgba = over(rgba, RING, a)

    for star in SPARKLES:
        a = coverage(sparkle(x, y, star), pixel)
        if a > 0:
            glow = min(math.hypot(x - star[0], y - star[1]) / star[2], 1.0)
            color = tuple(SPARKLE_INNER[i] + (SPARKLE_OUTER[i] - SPARKLE_INNER[i]) * glow for i in range(3))
            rgba = over(rgba, color, a)
    return rgba


def render(size):
    scale = size / 1024
    pixel = 1 / scale
    rows = []
    for py in range(size):
        row = bytearray([0])  # PNG filter type: none
        y = (py + 0.5) * pixel
        for px in range(size):
            r, g, b, a = shade((px + 0.5) * pixel, y, pixel)
            row += bytes(round(c * 255) for c in (r, g, b, a))
        rows.append(bytes(row))
    return b"".join(rows)


def png(size, raw):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)  # 8-bit RGBA
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


# Menu bar icon: a template (black + alpha) glyph on an 18 pt canvas; the system tints it.
MENU_OUTPUT = ROOT / "calto/Resources/Assets.xcassets/MenuBarIcon.imageset"
MENU_PAGE = (2.0, 4.0, 14.5, 16.0, 2.6)
MENU_STROKE = 1.35
MENU_HEADER_BOTTOM = 7.4
MENU_RINGS = [(5.0, 2.2, 6.4, 5.6, 0.7), (10.1, 2.2, 11.5, 5.6, 0.7)]
MENU_SPARKLE = (13.6, 12.9, 5.4)
MENU_SPARKLE_POWER = 0.55
MENU_CLEARANCE = 1.1


def menu_alpha(x, y, pixel):
    page = rounded_rect(x, y, MENU_PAGE)
    outline = coverage(abs(page + MENU_STROKE / 2) - MENU_STROKE / 2, pixel)
    header = coverage(max(page, y - MENU_HEADER_BOTTOM), pixel)
    glyph = max(outline, header, *(coverage(rounded_rect(x, y, ring), pixel) for ring in MENU_RINGS))
    star = sparkle(x, y, MENU_SPARKLE, MENU_SPARKLE_POWER)
    # Cut a gap around the sparkle so it reads as a separate shape.
    glyph *= 1 - coverage(star - MENU_CLEARANCE, pixel)
    return max(glyph, coverage(star, pixel))


def render_menu_icon(size):
    pixel = 18 / size
    rows = []
    for py in range(size):
        row = bytearray([0])
        y = (py + 0.5) * pixel
        for px in range(size):
            a = menu_alpha((px + 0.5) * pixel, y, pixel)
            row += bytes((0, 0, 0, round(a * 255)))
        rows.append(bytes(row))
    return b"".join(rows)


def write_menu_icon():
    MENU_OUTPUT.mkdir(parents=True, exist_ok=True)
    images = []
    for scale in (1, 2):
        name = f"menubar_{scale}x.png"
        (MENU_OUTPUT / name).write_bytes(png(18 * scale, render_menu_icon(18 * scale)))
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x"})
        print(f"rendered {name}")
    contents = {
        "images": images,
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }
    (MENU_OUTPUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    write_menu_icon()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rendered = {}
    images = []
    for points, scale in SLOTS:
        pixels = points * scale
        name = f"icon_{pixels}.png"
        if pixels not in rendered:
            rendered[pixels] = png(pixels, render(pixels))
            (OUTPUT / name).write_bytes(rendered[pixels])
            print(f"rendered {name}")
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{points}x{points}"})

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    (OUTPUT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    (OUTPUT.parent / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


if __name__ == "__main__":
    main()
