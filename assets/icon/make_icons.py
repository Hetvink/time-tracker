"""Generates the Time Trak icon set (app, macOS, Android adaptive, tray)."""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)
SS = 4  # supersampling factor

INDIGO = (79, 70, 229)
VIOLET = (124, 58, 237)
CYAN = (6, 182, 212)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size):
    """Diagonal indigo → violet → cyan with a soft top-left light."""
    small = 256
    img = Image.new('RGB', (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            c = lerp(INDIGO, VIOLET, t / 0.55) if t < 0.55 else lerp(VIOLET, CYAN, (t - 0.55) / 0.45)
            # light from the top-left, darker toward the bottom-right corner
            d = math.hypot(x / small - 0.25, y / small - 0.2)
            light = max(0.0, 0.22 - d * 0.35)
            shade = max(0.0, (x + y) / (2 * small) - 0.75) * 0.35
            c = tuple(min(255, int(v + (255 - v) * light - v * shade)) for v in c)
            px[x, y] = c
    return img.resize((size, size), Image.BICUBIC)


def ellipse_points(cx, cy, rx, ry, rot, t0, t1, n=240):
    pts = []
    for i in range(n + 1):
        t = t0 + (t1 - t0) * i / n
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * math.cos(rot) - y * math.sin(rot),
                    cy + x * math.sin(rot) + y * math.cos(rot)))
    return pts


def stroke(draw, pts, width, fill):
    draw.line(pts, fill=fill, width=int(width), joint='curve')
    r = width / 2
    for (x, y) in (pts[0], pts[-1]):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=fill)


def glyph(size, color=(255, 255, 255), scale=1.0, mono=False):
    """Saturn-style mark: a clock disc with a tilted orbit ring around it.

    Colour version: white disc, indigo hands, white ring that turns violet
    where it passes in front of the disc. Mono (tray template): black disc
    with the hands and the front of the ring cut out.
    """
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    s = size * scale
    cx, cy = size / 2, size / 2
    disc_r = s * 0.25
    rot = math.radians(-20)
    rx, ry = s * 0.41, s * 0.14
    ring_w = s * 0.042
    ink = (0, 0, 0, 0) if mono else (67, 56, 202, 255)  # hands
    front_ring = (0, 0, 0, 0) if mono else (139, 92, 246, 255)
    solid = color + (255,)

    # Smooth ring: a true ellipse outline drawn level, then rotated.
    def ring_mask(width):
        m = Image.new('L', (size, size), 0)
        ImageDraw.Draw(m).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), outline=255, width=int(width))
        return m.rotate(math.degrees(-rot), resample=Image.BICUBIC, center=(cx, cy))

    # Lower (front) half of the ellipse, in the same rotated frame
    front = Image.new('L', (size, size), 0)
    ImageDraw.Draw(front).rectangle((0, cy, size, size), fill=255)
    front = front.rotate(math.degrees(-rot), resample=Image.BICUBIC, center=(cx, cy))
    disc_mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(disc_mask).ellipse((cx - disc_r, cy - disc_r, cx + disc_r, cy + disc_r), fill=255)

    def paint(mask, rgba):
        global_layer = Image.new('RGBA', (size, size), rgba)
        return mask, global_layer

    def over(base, mask, rgba):
        top = Image.new('RGBA', (size, size), rgba[:3] + (0,))
        top.putalpha(mask.point(lambda v: v * rgba[3] // 255))
        return Image.alpha_composite(base, top)

    def cut(base, mask):
        """Erase [mask] from [base] (for the mono template)."""
        a = base.split()[3]
        a = Image.composite(Image.new('L', (size, size), 0), a, mask)
        base.putalpha(a)
        return base

    def both(m1, m2):
        return Image.composite(m1, Image.new('L', (size, size), 0), m2)

    ring = ring_mask(ring_w)
    # 1. Whole ring, then the disc on top (hides the back of the ring)
    layer = over(layer, ring, solid)
    layer = over(layer, disc_mask, solid)
    # 2. Front of the ring across the disc, with a thin gap around it
    front_on_disc = both(both(ring, front), disc_mask)
    if mono:
        layer = cut(layer, both(both(ring_mask(ring_w * 1.9), front), disc_mask))
        layer = over(layer, front_on_disc, solid)
        layer = cut(layer, front_on_disc) if False else layer
    else:
        layer = over(layer, front_on_disc, front_ring)
    d = ImageDraw.Draw(layer)

    # 4. Hands: minute to 12, hour to 4 — a clear clock silhouette
    hw = s * 0.05
    for angle, length in ((0, 0.165), (120, 0.115)):
        a = math.radians(angle - 90)
        stroke(d, [(cx, cy), (cx + math.cos(a) * s * length, cy + math.sin(a) * s * length)], hw, ink)
    r = s * 0.038
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ink)

    # 5. Satellite riding the ring (upper right, clear of the disc)
    t = math.radians(-35)
    x, y = rx * math.cos(t), ry * math.sin(t)
    sx, sy = cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)
    sr = s * 0.05
    if not mono:
        glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(glow).ellipse((sx - sr * 2.2, sy - sr * 2.2, sx + sr * 2.2, sy + sr * 2.2), fill=(165, 243, 252, 170))
        layer = Image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(sr * 0.9)), layer)
        d = ImageDraw.Draw(layer)
    d.ellipse((sx - sr, sy - sr, sx + sr, sy + sr), fill=solid if mono else (224, 252, 255, 255))
    return layer


def shadowed(layer, size, blur, alpha):
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    a = layer.split()[3].point(lambda v: int(v * alpha))
    shadow.putalpha(a)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    return shadow


def full_bleed(size=1024):
    big = size * SS
    bg = gradient(big).convert('RGBA')
    g = glyph(big)
    sh = shadowed(g, big, big * 0.012, 0.35)
    off = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    off.paste(sh, (0, int(big * 0.01)))
    img = Image.alpha_composite(Image.alpha_composite(bg, off), g)
    return img.resize((size, size), Image.LANCZOS)


def rounded_mask(size, inset, radius):
    m = Image.new('L', (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle((inset, inset, size - inset, size - inset), radius=radius, fill=255)
    return m


# 1. App icon (iOS / Android legacy / web / Windows): opaque, full bleed
app = full_bleed()
app.convert('RGB').save(os.path.join(OUT, 'app_icon.png'))

# 2. macOS: rounded tile inside the standard 1024 canvas with a drop shadow
big = 1024 * SS
tile = full_bleed(824).resize((824 * SS, 824 * SS), Image.LANCZOS)
canvas = Image.new('RGBA', (big, big), (0, 0, 0, 0))
mask = rounded_mask(824 * SS, 0, int(185 * SS))
shadow = Image.new('RGBA', (big, big), (0, 0, 0, 0))
sm = Image.new('L', (big, big), 0)
sm.paste(mask.point(lambda v: int(v * 0.45)), (100 * SS, 112 * SS))
shadow.putalpha(sm.filter(ImageFilter.GaussianBlur(14 * SS)))
canvas = Image.alpha_composite(canvas, shadow)
tile.putalpha(mask)
canvas.paste(tile, (100 * SS, 100 * SS), tile)
# hairline highlight on the tile edge
edge = Image.new('RGBA', (big, big), (0, 0, 0, 0))
ImageDraw.Draw(edge).rounded_rectangle((100 * SS, 100 * SS, 924 * SS, 924 * SS), radius=185 * SS, outline=(255, 255, 255, 60), width=3 * SS)
canvas = Image.alpha_composite(canvas, edge)
canvas.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, 'app_icon_macos.png'))

# 3. Android adaptive: glyph inside the 66% safe zone + gradient background
# flutter_launcher_icons adds a 16% inset, which keeps this in the safe zone
fg = glyph(big)
fg.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, 'adaptive_foreground.png'))
gradient(1024).save(os.path.join(OUT, 'adaptive_background.png'))

# 4. Tray: black template glyph for the macOS menu bar, coloured .ico for Windows
tray = glyph(64 * SS, color=(0, 0, 0), scale=1.12, mono=True).resize((64, 64), Image.LANCZOS)
tray.save(os.path.join(OUT, 'tray_icon.png'))
full_bleed(256).save(os.path.join(OUT, 'tray_icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (256, 256)])
print('icons written to', OUT)
