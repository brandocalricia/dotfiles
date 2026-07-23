#!/usr/bin/env bash
# rusty-bar-watch.sh — make the Rusty's Retirement bar dynamic, responsive, and
# host-agnostic (works on the desktop's HDMI-A-1 and the laptop's single screen).
#
# Rusty's Retirement runs inside gamescope (a fixed-size window it can't force-
# fullscreen out of; host window class = "gamescope"). gamescope opens it off-
# position and the game can't be docked by static rules, so this watcher:
#   * snaps the gamescope window to the bottom of workspace 1, on whatever monitor
#     workspace 1 lives on;
#   * reserves that window's height on that monitor ONLY while workspace 1 is the
#     one being viewed there — so no other workspace/monitor is ever squished, and
#     the reserve is dropped the instant you leave ws1 or close the game.
# Everything keys off the gamescope window, so nothing else is affected.
# Singleton via flock. Self-heals a fresh launch every poll. Started at login.
set -u

WS=1            # workspace the bar lives on ("profile 1")
POLL=0.35       # seconds between checks
SNAP_TOL=12     # px drift tolerated before re-snapping

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/rusty-bar-watch.lock"
flock -n 9 || exit 0        # another instance already running -> quit quietly

resmon=""; reserved=0
set_reserve(){ # $1 monitor-name  $2 px
  hyprctl keyword monitor "$1,addreserved,0,$2,0,0" >/dev/null 2>&1
  resmon="$1"; reserved="$2"
}
drop_reserve(){ [ -n "$resmon" ] && [ "$reserved" != 0 ] && hyprctl keyword monitor "$resmon,addreserved,0,0,0,0" >/dev/null 2>&1; reserved=0; }
trap 'drop_reserve; exit 0' INT TERM
trap drop_reserve EXIT

while :; do
  # gamescope (Rusty) window: "addr x y ws monIdx height"  (empty line if absent)
  read -r addr x y gws gmon gh < <(hyprctl clients -j 2>/dev/null | python3 -c '
import json,sys
try: cs=json.load(sys.stdin)
except Exception: sys.exit()
for c in cs:
    if (c.get("class") or "")=="gamescope":
        a=c.get("at") or [0,0]; s=c.get("size") or [0,0]
        print(c["address"], a[0], a[1], (c.get("workspace") or {}).get("id",0),
              c.get("monitor",-1), s[1]); break
' 2>/dev/null)

  if [ -z "${addr:-}" ]; then
    drop_reserve; resmon=""; sleep "$POLL"; continue
  fi

  # Make sure it's on ws1; if we had to move it, re-read next loop.
  if [ "${gws:-0}" != "$WS" ]; then
    hyprctl dispatch movetoworkspacesilent "$WS,address:$addr" >/dev/null 2>&1
    sleep "$POLL"; continue
  fi

  # Geometry + visible-workspace of the monitor the bar is on (found by index).
  read -r mname mx my mw mh mactive < <(hyprctl monitors -j 2>/dev/null | python3 -c '
import json,sys
want='"${gmon:--1}"'
for m in json.load(sys.stdin):
    if m.get("id")==want:
        print(m["name"],m["x"],m["y"],m["width"],m["height"],(m.get("activeWorkspace") or {}).get("id",0)); break
' 2>/dev/null)
  [ -z "${mname:-}" ] && { sleep "$POLL"; continue; }

  H="${gh:-450}"; [ "$H" -lt 50 ] && H=450
  tx=$mx; ty=$(( my + mh - H ))
  dx=$(( x>tx ? x-tx : tx-x )); dy=$(( y>ty ? y-ty : ty-y ))
  if [ "$dx" -gt "$SNAP_TOL" ] || [ "$dy" -gt "$SNAP_TOL" ]; then
    hyprctl dispatch movewindowpixel "exact $tx $ty,address:$addr" >/dev/null 2>&1
  fi

  # Reserve only while ws1 is the one being viewed on this monitor.
  if [ "${mactive:-0}" = "$WS" ]; then
    { [ "$resmon" != "$mname" ] || [ "$reserved" != "$H" ]; } && set_reserve "$mname" "$H"
  else
    drop_reserve
  fi
  sleep "$POLL"
done
