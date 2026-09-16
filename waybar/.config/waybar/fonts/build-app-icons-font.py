#!/usr/bin/env python3
"""Build WaybarAppIcons: color Brave + NordVPN logos at Nerd Font size.

U+E900 Brave, U+E901 NordVPN. Metrics match JetBrainsMono Nerd Font
(UPM 1000, width 600, icons in ~y -50..790) so they sit with /󰚩/󰌌.
Color is an sbix PNG strike; CSS color is ignored for these two.

Rebuild (fonttools + magick):
  python3 build-app-icons-font.py
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DIR = Path(__file__).resolve().parent
SRC = DIR / "src"
OUT = DIR / "waybar-app-icons.ttf"

BRAVE_CP = 0xE900
NORD_CP = 0xE901

UPM = 1000
ADVANCE = 600
ASCENT = 1020
DESCENT = -300
# Same optical box as the Nerd Font workspace icons.
DEST = (70, -50, 930, 790)  # xMin, yMin, xMax, yMax
STRIKES = (32, 64)


def _empty_glyph():
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    return TTGlyphPen(None).glyph()


def _origin_y_px(ppem: int) -> int:
    """Pixels from the image bottom to the baseline (DEST yMin is below it)."""
    return max(0, round((-DEST[1]) / UPM * ppem))


def _fit_color(src: Path, canvas: int) -> bytes:
    """Place the logo in DEST on a transparent canvas of `canvas` px."""
    if not src.is_file():
        sys.exit(f"missing {src}")
    dx0, dy0, dx1, dy1 = DEST
    logo_w = max(1, round((dx1 - dx0) / UPM * canvas))
    logo_h = max(1, round((dy1 - dy0) / UPM * canvas))
    left = round(dx0 / UPM * canvas)
    origin_y_upm = -dy0
    image_top_font = UPM - origin_y_upm
    top = round((image_top_font - dy1) / UPM * canvas)
    dest = Path(tempfile.mkstemp(suffix=".png")[1])
    try:
        subprocess.check_call(
            [
                "magick",
                "-size",
                f"{canvas}x{canvas}",
                "xc:none",
                "(",
                str(src),
                "-resize",
                f"{logo_w}x{logo_h}",
                ")",
                "-geometry",
                f"+{left}+{top}",
                "-composite",
                str(dest),
            ]
        )
        return dest.read_bytes()
    finally:
        dest.unlink(missing_ok=True)


def _nord_src() -> Path:
    svg = SRC / "nordvpn.svg"
    png = SRC / "nordvpn.png"
    if svg.is_file():
        return svg
    if png.is_file():
        return png
    sys.exit(f"missing {svg} or {png}")


def build(out: Path = OUT) -> Path:
    from fontTools.fontBuilder import FontBuilder
    from fontTools.ttLib import newTable
    from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
    from fontTools.ttLib.tables.sbixStrike import Strike

    brave_src = SRC / "brave.png"
    nord_src = _nord_src()

    glyph_order = [".notdef", "space", "brave", "nordvpn"]
    cmap = {BRAVE_CP: "brave", NORD_CP: "nordvpn", 0x20: "space"}
    empty = _empty_glyph()

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf({name: empty for name in glyph_order})
    fb.setupHorizontalMetrics({name: (ADVANCE, 0) for name in glyph_order})
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable(
        {
            "familyName": "WaybarAppIcons",
            "styleName": "Regular",
            "uniqueFontIdentifier": "WaybarAppIcons Regular",
            "fullName": "WaybarAppIcons Regular",
            "psName": "WaybarAppIcons-Regular",
            "version": "Version 3.0",
        }
    )
    fb.setupOS2(
        sTypoAscender=ASCENT,
        sTypoDescender=DESCENT,
        usWinAscent=ASCENT,
        usWinDescent=-DESCENT,
    )
    fb.setupPost()

    sbix = newTable("sbix")
    sbix.version = 1
    sbix.flags = 1  # bitmaps only, no outline overlay
    for ppem in STRIKES:
        oy = _origin_y_px(ppem)
        strike = Strike(ppem=ppem, resolution=72)
        strike.glyphs["brave"] = SbixGlyph(
            glyphName="brave",
            graphicType="png ",
            imageData=_fit_color(brave_src, ppem),
            originOffsetX=0,
            originOffsetY=oy,
        )
        strike.glyphs["nordvpn"] = SbixGlyph(
            glyphName="nordvpn",
            graphicType="png ",
            imageData=_fit_color(nord_src, ppem),
            originOffsetX=0,
            originOffsetY=oy,
        )
        sbix.strikes[ppem] = strike
    fb.font["sbix"] = sbix

    out.parent.mkdir(parents=True, exist_ok=True)
    fb.font.save(out)
    local_fonts = Path.home() / ".local/share/fonts"
    local_fonts.mkdir(parents=True, exist_ok=True)
    shutil.copy2(out, local_fonts / out.name)
    return out


if __name__ == "__main__":
    path = build()
    print(f"wrote {path}")
    print(f"copied to {Path.home() / '.local/share/fonts' / path.name}")
