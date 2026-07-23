#!/usr/bin/env bash
# rusty-bar-watch.sh — make the Rusty's Retirement bar dynamic & responsive.
#
# The game runs inside gamescope (fixed 2560x450 window). gamescope launches it
# off-position, so we SNAP it to the bottom of workspace 1. We reserve its height
# on HDMI-A-1 ONLY while (a) the game is running AND (b) workspace 1 is the one
# actually being viewed on that monitor — so other workspaces (a browser on ws2)
# are never squished, and the reserve is dropped the instant the game closes or you
# switch away from ws1. Keys off the gamescope window only -> affects nothing else.
# Singleton via flock. Started from local.<host>.conf.
set -u

MON="HDMI-A-1"     # monitor the bar docks to
BAR_H=450          # gamescope window height (keep in sync with the launch option)
WS=1               # workspace the bar lives on
POLL=0.4           # seconds between checks (responsiveness)
SNAP_TOL=15        # px tolerance before re-snapping position

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/rusty-bar-watch.lock"
flock -n 9 || exit 0        # another instance already running -> exit quietly

reserved=0
set_reserve(){ # $1 = px
  hyprctl keyword monitor "$MON,addreserved,0,$1,0,0" >/dev/null 2>&1
  reserved=$1
}
cleanup(){ [ "$reserved" != 0 ] && set_reserve 0; }
trap 'cleanup; exit 0' INT TERM
trap cleanup EXIT

while :; do
  # gamescope (Rusty) window: "addr x y ws" or empty if absent
  read -r addr x y gws < <(hyprctl clients -j 2>/dev/null | python3 -c '
import json,sys
try: cs=json.load(sys.stdin)
except Exception: sys.exit()
for c in cs:
    if (c.get("class") or "")=="gamescope":
        a=c.get("at") or [0,0]
        print(c["address"], a[0], a[1], (c.get("workspace") or {}).get("id",0)); break
' 2>/dev/null)

  # monitor geometry + which workspace is currently visible on it
  read -r mx my mw mh activews < <(hyprctl monitors -j 2>/dev/null | python3 -c '
import json,sys
for m in json.load(sys.stdin):
    if m["name"]=="'"$MON"'":
        print(m["x"],m["y"],m["width"],m["height"],(m.get("activeWorkspace") or {}).get("id",0)); break
' 2>/dev/null)

  if [ -n "${addr:-}" ] && [ -n "${mh:-}" ]; then
    # keep the bar on ws1 and snapped to the monitor's bottom-left
    [ "${gws:-0}" != "$WS" ] && hyprctl dispatch movetoworkspacesilent "$WS,address:$addr" >/dev/null 2>&1
    tx=$mx; ty=$(( my + mh - BAR_H ))
    dx=$(( x>tx ? x-tx : tx-x )); dy=$(( y>ty ? y-ty : ty-y ))
    if [ "$dx" -gt "$SNAP_TOL" ] || [ "$dy" -gt "$SNAP_TOL" ]; then
      hyprctl dispatch movewindowpixel "exact $tx $ty,address:$addr" >/dev/null 2>&1
    fi
    # reserve ONLY while ws1 is the visible workspace on this monitor
    if [ "${activews:-0}" = "$WS" ]; then
      [ "$reserved" != "$BAR_H" ] && set_reserve "$BAR_H"
    else
      [ "$reserved" != 0 ] && set_reserve 0
    fi
  else
    # game gone -> release the reserved space immediately
    [ "$reserved" != 0 ] && set_reserve 0
  fi
  sleep "$POLL"
done
