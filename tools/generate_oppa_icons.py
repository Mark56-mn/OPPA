#!/usr/bin/env python3
"""Generate OPPA launcher icons + adaptive layers + launch splash.

Renders the SAME geometry as the in-app vector brand painter
(lib/design/oppa_brand.dart: OppaPulsePainter) — glowing violet sphere with
three woven elliptical trails (blue, magenta, amber) — so the launcher icon,
splash and app UI all carry the identical approved mark. No external image
assets are used or produced beyond the generated PNGs.

Usage:
    python3 tools/generate_oppa_icons.py          # writes all mipmaps + splash
    python3 tools/generate_oppa_icons.py --check  # exit 0 when up to date
"""
import argparse
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

try:
    import numpy as np
except ImportError:  # pragma: no cover
    print("numpy is required: pip install numpy pillow", file=sys.stderr)
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "apps", "mobile", "android", "app", "src", "main", "res")

# Brand constants — must match oppa_brand.dart / oppa_themes.dart.
BG_TOP = (11, 2, 19)        # #0B0213 (Pulse background)
BG_BOTTOM = (23, 16, 34)    # #171022 (Pulse surface)
SPHERE_IN = (96, 165, 250)  # #60A5FA
SPHERE_MID = (124, 58, 237)  # #7C3AED
SPHERE_OUT = (46, 16, 101)  # #2E1065
TRAIL_BLUE = (96, 165, 250)
TRAIL_MAGENTA = (229, 57, 158)
TRAIL_AMBER = (245, 158, 11)

# (rotation, widthFactor, heightFactor, strokeWidth) — matches _TrailSpec.
TRAILS = [
    (0.15 * math.pi, 1.00, 0.62, 0.20),
    (0.62 * math.pi, 0.96, 0.58, 0.22),
    (1.12 * math.pi, 0.88, 0.52, 0.26),
]

SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def _hex(c):
    return "#{:02X}{:02X}{:02X}".format(*c)


def render_orb(size: int, ss: int = 2) -> Image.Image:
    """RGB square: Pulse bg + sphere + trails. Row-chunked to stay light on
    memory (the 1024 master renders comfortably inside small CI/sandbox VMs)."""
    px = size * ss
    cx = cy = (px - 1) / 2.0
    chunk = 128
    out_img = Image.new("RGB", (px, px))
    for y0 in range(0, px, chunk):
        y1 = min(y0 + chunk, px)
        yy, xx = np.mgrid[y0:y1, 0:px].astype(np.float64)
        r = np.sqrt(((xx - cx) / (px / 2.0)) ** 2 + ((yy - cy) / (px / 2.0)) ** 2)

        # background: vertical Pulse gradient
        t = np.clip(yy / px, 0, 1)[..., None]
        out = np.array(BG_TOP) * (1 - t) + np.array(BG_BOTTOM) * t

        # sphere: radial gradient, highlight offset top-left (as in the mark)
        sx = (xx - cx) / (px * 0.44) + 0.30
        sy = (yy - cy) / (px * 0.44) + 0.40
        stop = np.clip(np.sqrt(sx * sx + sy * sy), 0, 1.6)
        s = np.empty_like(out)
        lo = stop < 0.55
        for i in range(3):
            s[..., i] = np.where(
                lo,
                SPHERE_IN[i] + (SPHERE_MID[i] - SPHERE_IN[i]) * (stop / 0.55),
                SPHERE_MID[i] + (SPHERE_OUT[i] - SPHERE_MID[i])
                * ((stop - 0.55) / 1.05),
            )
        edge = np.clip((0.88 - r) / 0.06, 0, 1)[..., None]  # soft sphere edge
        out = out * (1 - edge) + s * edge

        # three elliptical trails (sweep-bright, as in the approved mark)
        for (rot, wf, hf, sw), col in zip(TRAILS, (TRAIL_BLUE, TRAIL_MAGENTA, TRAIL_AMBER)):
            rx, ry = px / 2.0 * 0.88 * wf, px / 2.0 * 0.88 * hf
            cosr, sinr = math.cos(-rot), math.sin(-rot)
            ux = (xx - cx) * cosr - (yy - cy) * sinr
            uy = (xx - cx) * sinr + (yy - cy) * cosr
            d = np.sqrt((ux / rx) ** 2 + (uy / ry) ** 2)
            band = np.abs(d - 1.0)
            fall = np.clip(1.0 - band / (sw * 2.2 * 0.88), 0, 1)
            ang01 = (np.arctan2(uy / ry, ux / rx) + math.pi) / (2 * math.pi)
            sweep = 0.15 + 0.85 * np.clip(1.0 - np.abs(ang01 - 0.55) / 0.45, 0, 1)
            inten = (fall * sweep)[..., None]
            out = out * (1 - inten) + np.array(col) * inten

        # highlight sparkle top-left
        hx, hy = cx - px * 0.15, cy - px * 0.185
        hs = np.sqrt((xx - hx) ** 2 + (yy - hy) ** 2)
        spark = (np.clip(1 - hs / (px * 0.03), 0, 1) ** 2)[..., None]
        out = out * (1 - spark * 0.9) + 255 * spark * 0.9

        out_img.paste(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB"), (0, y0))
    return out_img.resize((size, size), Image.LANCZOS)


def render_wordmark(orb: Image.Image, out_w: int, out_h: int, *, splash: bool) -> Image.Image:
    """Orb centered + OPPA wordmark + PULSE tagline (splash uses 1080x1920)."""
    scale = out_w / 10.0
    orb_size = int(scale * 3.6)
    o = orb.resize((orb_size, orb_size), Image.LANCZOS)
    img = Image.new("RGB", (out_w, out_h), BG_TOP)
    d = ImageDraw.Draw(img)
    # vertical gradient
    for y in range(out_h):
        t = y / out_h
        c = tuple(int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3))
        d.line([(0, y), (out_w, y)], fill=c)
    y0 = int(out_h * (0.30 if splash else 0.16))
    img.paste(o, ((out_w - orb_size) // 2, y0))
    d = ImageDraw.Draw(img)
    try:
        from PIL import ImageFont
        font_bold = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(scale * 0.78))
        font_tag = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", int(scale * 0.30))
    except Exception:  # pragma: no cover
        font_bold = font_tag = None
    wm = "OPPA"
    tag = "P U L S E"
    wb = d.textbbox((0, 0), wm, font=font_bold)
    tb = d.textbbox((0, 0), tag, font=font_tag)
    wx = (out_w - (wb[2] - wb[0])) // 2 - wb[0]
    wy = y0 + orb_size + int(scale * 0.42)
    d.text((wx, wy), wm, fill=(255, 255, 255), font=font_bold)
    tx = (out_w - (tb[2] - tb[0])) // 2 - tb[0]
    ty = wy + (wb[3] - wb[1]) + int(scale * 0.30)
    d.text((tx, ty), tag, fill=_hex_to_tuple("#7C3AED"), font=font_tag)
    return img


def _hex_to_tuple(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def render_adaptive_foreground(master: Image.Image, canvas: int = 432) -> Image.Image:
    """Transparent canvas with the orb inside the adaptive-icon safe zone
    (content circle ~66/108 of the canvas; orb drawn at ~55% for margin)."""
    orb_size = int(canvas * 0.55)
    o = master.resize((orb_size, orb_size), Image.LANCZOS)
    fg = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    # Circular crop so masked shapes never show square corners.
    mask = Image.new("L", (orb_size, orb_size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, orb_size, orb_size), fill=255)
    fg.paste(o, ((canvas - orb_size) // 2, (canvas - orb_size) // 2), mask)
    return fg


def write_all(check_only: bool) -> int:
    master = render_orb(512)
    changed = []
    for folder, size in SIZES.items():
        path = os.path.join(RES, folder, "ic_launcher.png")
        icon = master.resize((size, size), Image.LANCZOS)
        if check_only:
            if not os.path.exists(path):
                changed.append(path)
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        icon.save(path, optimize=True)
        changed.append(path)

    # Adaptive icon foreground (API 26+): orb in the safe zone on
    # transparency; the background layer is @color/oppa_launch_bg.
    fg_path = os.path.join(RES, "drawable", "oppa_icon_foreground.png")
    if not check_only:
        render_adaptive_foreground(master).save(fg_path, optimize=True)
        changed.append(fg_path)
    elif not os.path.exists(fg_path):
        changed.append(fg_path)

    # Splash: full-bleed brand screen (portrait), referenced by
    # drawable/launch_background.xml.
    splash_path = os.path.join(RES, "drawable", "oppa_launch.png")
    if not check_only:
        render_wordmark(master, 1080, 1920, splash=True).save(splash_path, optimize=True)
        changed.append(splash_path)
    elif not os.path.exists(splash_path):
        changed.append(splash_path)

    if check_only:
        if changed:
            print("MISSING: " + ", ".join(changed))
            return 1
        print("icons up to date")
        return 0

    for p in changed:
        print("wrote", os.path.relpath(p, ROOT))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify outputs exist")
    sys.exit(write_all(ap.parse_args().check))
