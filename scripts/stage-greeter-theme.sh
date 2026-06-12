#!/usr/bin/env bash
# Stage a tuigreet --theme string for the current palette.
# Usage: stage-greeter-theme.sh <accent-hex-without-#>
# tuigreet only accepts named ANSI colors, so we map the accent by HUE
# (pastel accents are near-white in RGB distance; hue is what identifies them).
# Applied to /etc/greetd/config.toml later via: sudo sh ~/dotfiles/scripts/greeter-apply.sh

set -eu
accent="$1"
python3 - "$accent" <<'PYEOF'
import sys, colorsys, os
hexstr = sys.argv[1].lstrip("#")
r, g, b = (int(hexstr[i:i+2], 16)/255 for i in (0, 2, 4))
h, l, s = colorsys.rgb_to_hls(r, g, b)
if s < 0.12:
    acc = "white" if l > 0.65 else "gray"
else:
    deg = (h * 360) % 360
    for limit, name in [(20, "lightred"), (75, "lightyellow"),
                        (160, "lightgreen"), (215, "lightcyan"),
                        (262, "lightblue"), (330, "lightmagenta"),
                        (360, "lightred")]:
        if deg <= limit:
            acc = name
            break
theme = (f"container=black;border={acc};title={acc};greet={acc};"
         f"prompt={acc};input=white;text=gray;time={acc};"
         f"action=gray;button={acc}")
d = os.path.expanduser("~/.cache/dynamic-theme")
os.makedirs(d, exist_ok=True)
open(f"{d}/tuigreet.txt", "w").write(theme + "\n")
print(f"greeter staged: {acc}")
PYEOF
