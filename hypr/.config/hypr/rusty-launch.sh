#!/usr/bin/env bash
# rusty-launch.sh — Steam launch wrapper for Rusty's Retirement (app 2666510).
# Runs the game inside gamescope sized to the FULL WIDTH of whatever monitor hosts
# workspace 1, at a fixed bar height. This keeps the same launch option working on
# any machine (desktop HDMI-A-1, laptop eDP-1) — the width is detected at runtime.
#
# Set as the Steam launch option (identical on every host):
#   ~/.config/hypr/rusty-launch.sh %command%
#
# rusty-bar-watch.sh then snaps this gamescope window to the bottom of ws1 and
# reserves its height while ws1 is in view. Height here must match BAR_H there.
set -u
BAR_H=450

# Width of the monitor that OWNS workspace 1 (fallback: focused monitor, then 1920).
W=$(
  mon_name=$(hyprctl workspaces -j 2>/dev/null | python3 -c '
import json,sys
try: ws=json.load(sys.stdin)
except Exception: ws=[]
print(next((w.get("monitor","") for w in ws if w.get("id")==1),""))
' 2>/dev/null)
  hyprctl monitors -j 2>/dev/null | python3 -c '
import json,sys
name="'"${mon_name:-}"'"
try: mons=json.load(sys.stdin)
except Exception: mons=[]
w=0
if name:
    w=next((m.get("width",0) for m in mons if m.get("name")==name),0)
if not w:
    w=next((m.get("width",0) for m in mons if m.get("focused")),0)
if not w and mons: w=mons[0].get("width",0)
print(w or 1920)
' 2>/dev/null
)
[ -z "$W" ] && W=1920

exec gamescope -W "$W" -H "$BAR_H" -w "$W" -h "$BAR_H" -- "$@"
