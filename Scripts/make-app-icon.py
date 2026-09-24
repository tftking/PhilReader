# Draws the PhilReader app icon (1024x1024). Requires Pillow:
#   python3 -m venv .venv && .venv/bin/pip install pillow
#   .venv/bin/python Scripts/make-app-icon.py PhilReader/Assets.xcassets/AppIcon.appiconset/AppIcon.png
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math, sys
S = 1024
SS = 2  # supersample
W = S * SS

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# Diagonal three-stop gradient background.
stops = [(0.0, (255, 122, 92)), (0.5, (226, 50, 104)), (1.0, (74, 32, 140))]
bg = Image.new('RGB', (W, W))
px = bg.load()
for y in range(W):
    for x in range(W):
        t = (x * 0.45 + y * 0.55) / W
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                px[x, y] = lerp(c0, c1, (t - t0) / (t1 - t0)); break
        else:
            px[x, y] = stops[-1][1]

# Soft radial glow top-left.
glow = Image.new('L', (W, W), 0)
ImageDraw.Draw(glow).ellipse([-W*0.25, -W*0.35, W*0.75, W*0.55], fill=90)
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.12))
bg = Image.composite(Image.new('RGB', (W, W), (255, 230, 210)), bg, glow)

def page_layer():
    """A white comic page with a panel grid, drawn upright, then rotated."""
    pw, ph = int(W * 0.50), int(W * 0.66)
    layer = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0 = (W - pw) // 2 - int(W * 0.04), (W - ph) // 2 + int(W * 0.03)
    r = int(W * 0.035)
    d.rounded_rectangle([x0, y0, x0 + pw, y0 + ph], r, fill=(255, 255, 255, 255))
    m, g = int(W * 0.035), int(W * 0.022)
    ink = (38, 24, 58, 255)
    tint = (255, 236, 232, 255)
    ix0, iy0, ix1, iy1 = x0 + m, y0 + m, x0 + pw - m, y0 + ph - m
    rows = [0.36, 0.30, 0.34]
    y = iy0
    lw = int(W * 0.012)
    for i, frac in enumerate(rows):
        h = (iy1 - iy0 - g * (len(rows) - 1)) * frac
        if i == 1:
            wsplit = (ix1 - ix0 - g) * 0.42
            boxes = [(ix0, y, ix0 + wsplit, y + h), (ix0 + wsplit + g, y, ix1, y + h)]
        else:
            boxes = [(ix0, y, ix1, y + h)]
        for b in boxes:
            d.rounded_rectangle(b, int(W * 0.008), fill=tint, outline=ink, width=lw)
        y += h + g
    return layer

page = page_layer().rotate(-7, resample=Image.BICUBIC, center=(W / 2, W / 2))
shadow = page.split()[3].filter(ImageFilter.GaussianBlur(W * 0.025))
shadow_img = Image.new('RGBA', (W, W), (40, 0, 60, 0))
shadow_img.putalpha(shadow.point(lambda a: int(a * 0.45)))
out = bg.convert('RGBA')
out.alpha_composite(shadow_img, (int(W * 0.012), int(W * 0.03)))
out.alpha_composite(page)

# Speech bubble, top right, overlapping the page.
bubble = Image.new('RGBA', (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(bubble)
cx, cy, rx, ry = W * 0.70, W * 0.27, W * 0.17, W * 0.125
ink = (38, 24, 58, 255)
lw = int(W * 0.014)
tail = [(cx - rx * 0.55, cy + ry * 0.55), (cx - rx * 1.05, cy + ry * 1.55), (cx - rx * 0.05, cy + ry * 0.85)]
d.polygon(tail, fill=ink)
d.ellipse([cx - rx - lw, cy - ry - lw, cx + rx + lw, cy + ry + lw], fill=ink)
inner_tail = [(cx - rx * 0.52, cy + ry * 0.45), (cx - rx * 0.92, cy + ry * 1.28), (cx - rx * 0.12, cy + ry * 0.72)]
d.polygon(inner_tail, fill=(255, 255, 255, 255))
d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(255, 255, 255, 255))
# Three dots: "reading…"
for i in (-1, 0, 1):
    r = W * 0.022
    dx = cx + i * W * 0.068
    d.ellipse([dx - r, cy - r, dx + r, cy + r], fill=(226, 50, 104, 255))
bshadow = bubble.split()[3].filter(ImageFilter.GaussianBlur(W * 0.02))
bs = Image.new('RGBA', (W, W), (40, 0, 60, 0)); bs.putalpha(bshadow.point(lambda a: int(a * 0.35)))
out.alpha_composite(bs, (int(W * 0.01), int(W * 0.022)))
out.alpha_composite(bubble)

icon = out.convert('RGB').resize((S, S), Image.LANCZOS)
icon.save(sys.argv[1])

