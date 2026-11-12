#!/usr/bin/env python3
"""Render glasses HUD dumps (tests, via SCREENS=dir and H.glasses) into PNG previews.

Usage: python3 tools/render_hud.py <dump dir> <output dir>

Each .hud line: kind, x, y, w, h, r, g, b, alpha, scale, text (tab separated), in GUI pixels with colors 0..1,
as OC Glasses takes them. Drawn at GUI scale 3 over a stone-like background, cropped to the HUD. Text is
DejaVu Sans Mono sized to OC Glasses' measured ~5.2 GUI px per character per unit of scale, so widths match;
the real font is Minecraft's pixel font.
"""
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

GUI = 3
FONTS = ["/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
         "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"]


def font(scale):
    size = max(6, int(round(5.2 * GUI * scale / 0.602)))
    for path in FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def background(w, h):
    rnd = random.Random(7)
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    block = 16 * GUI
    for by in range(0, h, block // 4):
        for bx in range(0, w, block // 4):
            v = rnd.randint(-14, 14)
            d.rectangle([bx, by, bx + block // 4, by + block // 4], fill=(92 + v, 78 + v, 66 + v))
    return img.convert("RGBA")


def render(path, out):
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 11:
                continue
            kind, x, y, w, h, r, g, b, a, s = p[0], *map(float, p[1:10])
            rows.append((kind, x, y, w, h, (r, g, b), a, s, p[10]))
    if not rows:
        return
    right = max(r[1] + max(r[3], len(r[8]) * 5.2 * r[7]) for r in rows) + 20
    bottom = max(r[2] + max(r[4], 10 * r[7]) for r in rows) + 20
    W, H = int(right * GUI), int(bottom * GUI)
    img = background(W, H)
    for kind, x, y, w, h, (r, g, b), a, s, text in rows:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        col = (int(min(r, 1) * 255), int(min(g, 1) * 255), int(min(b, 1) * 255), int(min(a, 1) * 255))
        if kind == "rect":
            d.rectangle([x * GUI, y * GUI, (x + w) * GUI - 1, (y + h) * GUI - 1], fill=col)
        elif kind == "text":
            d.text((x * GUI, y * GUI), text, font=font(s), fill=col)
        img = Image.alpha_composite(img, layer)
    img.convert("RGB").save(out)
    print("rendered " + os.path.basename(out))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    for name in sorted(os.listdir(src)):
        if name.endswith(".hud"):
            render(os.path.join(src, name), os.path.join(dst, name[:-4] + ".png"))


if __name__ == "__main__":
    main()
