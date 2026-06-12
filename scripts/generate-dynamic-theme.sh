#!/usr/bin/env bash
# Generate themes/dynamic.sh (+ btop theme + tuigreet staging) from a wallpaper.
# Usage: generate-dynamic-theme.sh <image>
# matugen is used purely as a palette oracle (--dry-run --json); all file
# output happens here so the template engine stays switch-theme.sh alone.
# Dark lock: only the .dark values are ever read; contrast is enforced below.

set -eu
img="$1"
[ -f "$img" ] || { echo "no such image: $img" >&2; exit 1; }

json_tmp=$(mktemp)
trap 'rm -f "$json_tmp"' EXIT
matugen image "$img" --dry-run --json hex -t scheme-vibrant -m dark 2>/dev/null > "$json_tmp"

python3 - "$img" "$json_tmp" <<'PYEOF'
import json, sys, colorsys, os, datetime

data = json.load(open(sys.argv[2]))
img = sys.argv[1]
C = {k: v["dark"].lstrip("#") for k, v in data["colors"].items()}

def hex2hls(h):
    r, g, b = (int(h[i:i+2], 16)/255 for i in (0, 2, 4))
    return colorsys.rgb_to_hls(r, g, b)

def hls2hex(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h % 1.0, max(0, min(1, l)), max(0, min(1, s)))
    return f"{round(r*255):02x}{round(g*255):02x}{round(b*255):02x}"

def luminance(h):
    def ch(c):
        c = int(h[i:i+2], 16)/255 if False else c
        return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    r, g, b = (int(h[i:i+2], 16)/255 for i in (0, 2, 4))
    return 0.2126*ch(r) + 0.7152*ch(g) + 0.0722*ch(b)

def contrast(fg, bg):
    l1, l2 = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (l1 + 0.05) / (l2 + 0.05)

def ensure_contrast(fg, bg, minimum):
    # raise fg lightness until it clears `minimum` against bg (dark lock:
    # backgrounds never change, text/accents only ever get lighter)
    h, l, s = hex2hls(fg)
    for _ in range(20):
        if contrast(fg, bg) >= minimum:
            return fg
        l = min(1.0, l + 0.04)
        fg = hls2hex(h, l, s)
    return fg

# ANSI semantic colors: fixed reference hues nudged toward the wallpaper's
# primary hue (cheap harmonization), pastel tone to match Material dark accents
prim_h, _, _ = hex2hls(C["primary"])
def harmonized(ref_hue_deg, sat=0.50, light=0.72):
    # nudge toward the wallpaper hue, hard-capped at 15deg so the color
    # keeps its identity (orange stays orange) — mirrors Material harmonize
    ref = ref_hue_deg / 360.0
    delta = (prim_h - ref + 0.5) % 1.0 - 0.5
    shift = max(-15/360, min(15/360, delta * 0.5))
    return hls2hex(ref + shift, light, sat)

BG_DARK = C["surface"]
pal = {
    "BG_DARK": BG_DARK,
    "BG_MID": C["surface_container"],
    "BG_LIGHT": C["surface_container_high"],
    "BG_LIGHTER": C["surface_container_highest"],
    "FG_DIM": ensure_contrast(C["on_surface_variant"], BG_DARK, 4.5),
    "FG_MID": ensure_contrast(C["on_surface"], BG_DARK, 4.5),
    "FG_BRIGHT": ensure_contrast(C["on_surface"], BG_DARK, 4.5),
    "ACCENT_PRIMARY": ensure_contrast(C["primary"], BG_DARK, 3.0),
    "ACCENT_SECONDARY": ensure_contrast(C["secondary"], BG_DARK, 3.0),
    "ACCENT_TERTIARY": ensure_contrast(C["tertiary"], BG_DARK, 3.0),
    "RED": ensure_contrast(C["error"], BG_DARK, 3.0),
    "ORANGE": harmonized(30),
    "YELLOW": harmonized(50),
    "GREEN": harmonized(130),
    "TEAL": harmonized(180),
    "PURPLE": harmonized(280),
    "BORDER_ACTIVE_1": C["primary"],
    "BORDER_ACTIVE_2": C["secondary"],
    "BORDER_INACTIVE": C["surface_container_low"],
    "BAR_BG": BG_DARK,
    "BAR_BORDER": C["surface_container"],
    "BAR_INACTIVE_WS": C["outline"],
}

home = os.environ["HOME"]
stamp = f"# Generated {datetime.date.today()} from {os.path.basename(img)} — DO NOT EDIT"

# themes/dynamic.sh — same shape as themes/blackgold.sh
with open(f"{home}/dotfiles/themes/dynamic.sh", "w") as f:
    f.write(f"# Dynamic wallpaper theme\n{stamp}\n")
    f.write('THEME_NAME="dynamic"\n')
    for k, v in pal.items():
        f.write(f'{k}="{v}"\n')
    f.write('BAR_ALPHA="0.92"\n')

# btop theme — mirrors btop/themes/blackgold.theme mapping
p = pal
btop = f"""# Name: dynamic
{stamp}
theme[main_bg]="#{p['BG_DARK']}"
theme[main_fg]="#{p['FG_BRIGHT']}"
theme[title]="#{p['FG_BRIGHT']}"
theme[hi_fg]="#{p['ACCENT_PRIMARY']}"
theme[selected_bg]="#{p['BG_LIGHT']}"
theme[selected_fg]="#{p['FG_BRIGHT']}"
theme[inactive_fg]="#{p['FG_DIM']}"
theme[graph_text]="#{p['FG_MID']}"
theme[meter_bg]="#{p['BG_MID']}"
theme[proc_misc]="#{p['ACCENT_SECONDARY']}"
theme[cpu_box]="#{p['ACCENT_SECONDARY']}"
theme[mem_box]="#{p['ORANGE']}"
theme[net_box]="#{p['GREEN']}"
theme[proc_box]="#{p['ACCENT_PRIMARY']}"
theme[div_line]="#{p['BG_LIGHTER']}"
theme[temp_start]="#{p['GREEN']}"
theme[temp_end]="#{p['RED']}"
theme[cpu_start]="#{p['GREEN']}"
theme[cpu_mid]="#{p['YELLOW']}"
theme[cpu_end]="#{p['RED']}"
theme[download_start]="#{p['TEAL']}"
theme[download_mid]="#{p['YELLOW']}"
theme[download_end]="#{p['ACCENT_PRIMARY']}"
theme[upload_start]="#{p['GREEN']}"
theme[upload_mid]="#{p['YELLOW']}"
theme[upload_end]="#{p['RED']}"
"""
with open(f"{home}/dotfiles/btop/.config/btop/themes/dynamic.theme", "w") as f:
    f.write(btop)

# tuigreet staging: nearest ratatui named color for the accent (greeter can
# only do named ANSI colors — approximation is the ceiling, documented)
# Map by HUE, not RGB distance: pastel Material accents are nearly white in
# RGB space but their hue is unmistakable. Buckets cover the named ANSI hues.
def nearest(hexstr):
    h, l, s = hex2hls(hexstr)
    if s < 0.12:
        return "white" if l > 0.65 else "gray"
    deg = (h * 360) % 360
    buckets = [(20, "lightred"), (48, "lightyellow"), (75, "lightyellow"),
               (160, "lightgreen"), (215, "lightcyan"), (262, "lightblue"),
               (330, "lightmagenta"), (360, "lightred")]
    for limit, name in buckets:
        if deg <= limit:
            return name
    return "white"

acc = nearest(pal["ACCENT_PRIMARY"])
theme_str = (f"container=black;border={acc};title={acc};greet={acc};"
             f"prompt={acc};input=white;text=gray;time={acc};"
             f"action=gray;button={acc}")
os.makedirs(f"{home}/.cache/dynamic-theme", exist_ok=True)
with open(f"{home}/.cache/dynamic-theme/tuigreet.txt", "w") as f:
    f.write(theme_str + "\n")

print(f"palette written: accent #{pal['ACCENT_PRIMARY']} on #{pal['BG_DARK']}"
      f" (contrast {contrast(pal['ACCENT_PRIMARY'], pal['BG_DARK']):.1f}:1)")
print(f"greeter staged: {acc}")
PYEOF
