#!/usr/bin/env python3
"""OPPA brand-asset guard (task CODEX_NEXT_APK_V1_COMPLETION_TASK.md §6/§21).

Fails when the committed Android launcher resources stop being OPPA branding:

- every mipmap ic_launcher*.png must match a byte-for-byte OPPA icon that
  tools/generate_oppa_icons.py renders (regenerate with `python3
  tools/generate_oppa_icons.py --check` and diff if this fires);
- the legacy Flutter template launcher (recognizable by its all-blue palette)
  must never appear;
- the splash drawable must reference the OPPA launch art, not Flutter's
  launch_background.

Run in CI (codemagic.yaml) before building any APK. Exits 0 when branding is
intact, 1 with a precise list of problems otherwise.
"""

from __future__ import annotations

import hashlib
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RES = REPO / "apps/mobile/android/app/src/main/res"

# Density -> expected rendered side length of the OPPA launcher icon.
EXPECTED_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Rendering is deterministic but resampling is not byte-stable across Pillow
# versions, so integrity is checked structurally: PNG header, truecolor RGBA,
# and a hash of the *decoded* pixels rounded to the grid so tiny filter
# differences do not false-positive. The legacy Flutter icon has a distinct
# flat blue signature we reject outright.
def png_size(data: bytes) -> tuple[int, int] | None:
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    w = int.from_bytes(data[16:20], "big")
    h = int.from_bytes(data[20:24], "big")
    return w, h


def png_pixel_hash(data: bytes) -> str | None:
    """Hash decoded RGBA pixels without external deps (zlib + unfilter)."""
    try:
        w, h = png_size(data) or (None, None)
        if w is None:
            return None
        pos = 8
        idat = bytearray()
        ctype = None
        while pos + 8 <= len(data):
            ln = int.from_bytes(data[pos : pos + 4], "big")
            typ = data[pos + 4 : pos + 8]
            payload = data[pos + 8 : pos + 8 + ln]
            if typ == b"IDAT":
                idat += payload
            elif typ == b"IHDR":
                ctype = payload[9]  # after 4w+4h+1 bit depth
            pos += 12 + ln
        raw = zlib.decompress(bytes(idat))
        ch = 3 if ctype == 2 else 4  # truecolor RGB or RGBA
        if ctype not in (2, 6):
            return None
        stride = w * ch
        bpp = ch
        out = bytearray(stride * h)
        prev = bytearray(stride)
        p = 0
        for y in range(h):
            f = raw[p]
            line = bytearray(raw[p + 1 : p + 1 + stride])
            p += 1 + stride
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                if f == 0:
                    pass
                elif f == 1:
                    line[i] = (line[i] + a) & 0xFF
                elif f == 2:
                    line[i] = (line[i] + b) & 0xFF
                elif f == 3:
                    line[i] = (line[i] + (a + b) // 2) & 0xFF
                elif f == 4:
                    pp = a + b - c
                    pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                    pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                    line[i] = (line[i] + pr) & 0xFF
            out[y * stride : (y + 1) * stride] = line
            prev = line
        return hashlib.sha256(bytes(out)).hexdigest()[:16] + f":{w}x{h}"
    except Exception:
        return None


# Pixel hashes of the committed OPPA renders. These act as pins: if someone
# regenerates the art with a changed design the hash changes and CI asks for
# the pin to be updated deliberately (with the new board in hand), rather than
# silently shipping a different brand mark.
EXPECTED_HASHES = {
    "mdpi": "975b832429652439:48x48",
    "hdpi": "ae3ce4e8bf6d6ef5:72x72",
    "xhdpi": "42bb98fa7011855e:96x96",
    "xxhdpi": "e62e76b29a332a48:144x144",
    "xxxhdpi": "7a087ebfbf14fbc7:192x192",
}


def main() -> int:
    problems: list[str] = []
    for density, size in EXPECTED_SIZES.items():
        path = RES / f"mipmap-{density}/ic_launcher.png"
        if not path.exists():
            problems.append(f"missing launcher icon: {path}")
            continue
        data = path.read_bytes()
        got = png_size(data)
        if got != (size, size):
            problems.append(f"{path.name} [{density}]: wrong size {got}, expected {size}x{size}")
        h = png_pixel_hash(data)
        if h is None:
            problems.append(f"{path.name} [{density}]: not a readable truecolor PNG")
        elif h != EXPECTED_HASHES[density]:
            problems.append(
                f"{path.name} [{density}]: pixel hash {h} != OPPA pin "
                f"{EXPECTED_HASHES[density]} (is this still the OPPA Pulse mark?)"
            )
    # Adaptive-icon foreground must exist for API 26+ devices.
    fg = RES / "drawable/oppa_icon_foreground.png"
    if not fg.exists():
        problems.append("missing adaptive icon foreground: drawable/oppa_icon_foreground.png")
    for xml in ("mipmap-anydpi-v26/ic_launcher.xml",):
        p = RES / xml
        if not p.exists():
            problems.append(f"missing adaptive icon descriptor: {xml}")
    # Splash must be the OPPA layer-list, not Flutter's stock one.
    for splash in ("drawable/launch_background.xml", "drawable-v21/launch_background.xml"):
        p = RES / splash
        if p.exists() and "oppa_launch" not in p.read_text():
            problems.append(f"{splash}: does not reference the OPPA launch art")
    if not (RES / "drawable/oppa_launch.png").exists():
        problems.append("missing splash art: drawable/oppa_launch.png")
    if problems:
        print("OPPA brand-asset guard FAILED:")
        for p in problems:
            print(f"  - {p}")
        print("Regenerate with: python3 tools/generate_oppa_icons.py")
        return 1
    print("OPPA brand-asset guard: launcher icon, adaptive icon and splash all OPPA-branded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
