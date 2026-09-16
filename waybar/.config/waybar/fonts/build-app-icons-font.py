#!/usr/bin/env python3
"""Build WaybarAppIcons: color bitmap font with the real Brave + NordVPN logos.

Waybar window-rewrite is text-only, so the official app PNGs are packed into a
tiny sbix+CBDT font at U+E900 (Brave) and U+E901 (NordVPN). Missing glyphs in
window-rewrite hide the window entirely — keep those codepoints filled.

Rebuild (fonttools required):
  python3 build-app-icons-font.py
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

DIR = Path(__file__).resolve().parent
SRC = DIR / "src"
OUT = DIR / "waybar-app-icons.ttf"

# Private Use; verified absent from JetBrainsMono Nerd Font on this host.
BRAVE_CP = 0xE900
NORD_CP = 0xE901


def _png(name: str) -> bytes:
    path = SRC / name
    if not path.is_file():
        sys.exit(f"missing source PNG: {path}")
    return path.read_bytes()


def _empty_glyph():
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    return TTGlyphPen(None).glyph()


def _square_outline(size: int = 900, pad: int = 62):
    """Fallback silhouette if a renderer ignores color bitmaps."""
    from fontTools.pens.ttGlyphPen import TTGlyphPen

    pen = TTGlyphPen(None)
    x0, y0 = pad, pad
    x1, y1 = pad + size, pad + size
    pen.moveTo((x0, y0))
    pen.lineTo((x1, y0))
    pen.lineTo((x1, y1))
    pen.lineTo((x0, y1))
    pen.closePath()
    return pen.glyph()


def build(out: Path = OUT) -> Path:
    from fontTools.fontBuilder import FontBuilder
    from fontTools.ttLib import newTable
    from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
    from fontTools.ttLib.tables.sbixStrike import Strike

    brave = _png("brave.png")
    nord = _png("nordvpn.png")

    glyph_order = [".notdef", "space", "brave", "nordvpn"]
    cmap = {BRAVE_CP: "brave", NORD_CP: "nordvpn", 0x20: "space"}

    fb = FontBuilder(1024, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)

    empty = _empty_glyph()
    square = _square_outline()
    fb.setupGlyf({".notdef": square, "space": empty, "brave": square, "nordvpn": square})
    metrics = {
        ".notdef": (1024, 62),
        "space": (512, 0),
        "brave": (1024, 62),
        "nordvpn": (1024, 62),
    }
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=960, descent=-64)
    fb.setupNameTable(
        {
            "familyName": "WaybarAppIcons",
            "styleName": "Regular",
            "uniqueFontIdentifier": "WaybarAppIcons Regular",
            "fullName": "WaybarAppIcons Regular",
            "psName": "WaybarAppIcons-Regular",
            "version": "Version 1.0",
        }
    )
    fb.setupOS2(sTypoAscender=960, sTypoDescender=-64, usWinAscent=960, usWinDescent=64)
    fb.setupPost()

    font = fb.font

    sbix = newTable("sbix")
    sbix.version = 1
    sbix.flags = 1
    for ppem in (32, 64):
        strike = Strike(ppem=ppem, resolution=72)
        strike.glyphs["brave"] = SbixGlyph(
            glyphName="brave", graphicType="png ", imageData=brave, originOffsetX=0, originOffsetY=0
        )
        strike.glyphs["nordvpn"] = SbixGlyph(
            glyphName="nordvpn", graphicType="png ", imageData=nord, originOffsetX=0, originOffsetY=0
        )
        sbix.strikes[ppem] = strike
    font["sbix"] = sbix

    out.parent.mkdir(parents=True, exist_ok=True)
    font.save(out)

    local_fonts = Path.home() / ".local/share/fonts"
    local_fonts.mkdir(parents=True, exist_ok=True)
    installed = local_fonts / out.name
    shutil.copy2(out, installed)
    return out


if __name__ == "__main__":
    path = build()
    print(f"wrote {path}")
    print(f"copied to {Path.home() / '.local/share/fonts' / path.name}")
