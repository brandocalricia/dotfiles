#!/usr/bin/env bash
# rusty-bar-watch.sh — dock the Rusty's Retirement (gamescope) bar and reserve its
# space dynamically. Host-agnostic (desktop HDMI-A-1, laptop eDP-1).
#
# Rusty's Retirement runs inside gamescope (a fixed-size window it can't force-
# fullscreen out of; host window class = "gamescope"). gamescope opens it centred,
# so this watcher snaps it to the bottom of workspace 1 on whatever monitor hosts
# ws1, and reserves that window's height on that monitor ONLY while ws1 is the
# workspace being viewed there — so nothing else is squished and the reserve clears
# the instant you leave ws1 or close the game.
#
# It also SELF-HEALS a stuck-fullscreen bug: fullscreening then exiting a video
# (e.g. YouTube in the browser) can leave a window stuck in Hyprland's *maximize*
# fullscreen state, which hides the floating bar behind it even though the window
# doesn't fill the screen. So when ws1 is in view, any non-bar window that is
# fullscreen-flagged but does NOT fill the monitor gets its fullscreen cleared
# (a TRUE fullscreen video fills the screen and is left alone — the bar stays
# hidden during it, as intended).
#
# ROBUSTNESS: a watcher must not outlive its Hyprland instance. After a logout the
# new session gets a new instance signature/socket; a survivor from the old one
# would hit a dead socket AND hold a global lock, blocking the fresh watcher. So
# the flock is PER-INSTANCE (keyed on HYPRLAND_INSTANCE_SIGNATURE) and the watcher
# self-exits when hyprctl stops responding (its instance died).
set -u

WS=1            # workspace the bar lives on ("profile 1")
POLL=0.35       # seconds between checks
SNAP_TOL=12     # px drift tolerated before re-snapping
DEAD_MAX=8      # consecutive hyprctl failures => our Hyprland instance is gone

SIG="${HYPRLAND_INSTANCE_SIGNATURE:-nosig}"
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/rusty-bar-watch.${SIG}.lock"
flock -n 9 || exit 0        # a watcher for THIS instance already runs -> quit

resmon=""; reserved=0; fails=0
set_reserve(){ hyprctl keyword monitor "$1,addreserved,0,$2,0,0" >/dev/null 2>&1; resmon="$1"; reserved="$2"; }
drop_reserve(){ [ -n "$resmon" ] && [ "$reserved" != 0 ] && hyprctl keyword monitor "$resmon,addreserved,0,0,0,0" >/dev/null 2>&1; reserved=0; }
trap 'drop_reserve; exit 0' INT TERM
trap drop_reserve EXIT

while :; do
  mons="$(hyprctl monitors -j 2>/dev/null)"
  if [ -z "$mons" ] || ! printf '%s' "$mons" | grep -q '"id"'; then
    fails=$((fails+1)); [ "$fails" -ge "$DEAD_MAX" ] && exit 0
    sleep "$POLL"; continue
  fi
  fails=0

  clients="$(hyprctl clients -j 2>/dev/null)"
  # gamescope (Rusty) window: "addr x y ws monIdx height" (empty if absent)
  read -r addr x y gws gmon gh < <(printf '%s' "$clients" | python3 -c '
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

  if [ "${gws:-0}" != "$WS" ]; then
    hyprctl dispatch movetoworkspacesilent "$WS,address:$addr" >/dev/null 2>&1
    sleep "$POLL"; continue
  fi

  read -r mname mx my mw mh mactive < <(printf '%s' "$mons" | python3 -c '
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

  if [ "${mactive:-0}" = "$WS" ]; then
    # Self-heal: clear stuck-maximize windows on ws1 that hide the bar. A window is
    # "stuck" if it's fullscreen-flagged but does NOT fill the monitor height (a real
    # fullscreen video fills it and is left alone). Clear at most one per poll.
    stuck="$(printf '%s' "$clients" | python3 -c '
import json,sys
mh='"$mh"'
try: cs=json.load(sys.stdin)
except Exception: sys.exit()
for c in cs:
    if (c.get("class") or "")=="gamescope": continue
    if (c.get("workspace") or {}).get("id",0)!='"$WS"': continue
    if not c.get("fullscreen"): continue
    if (c.get("size") or [0,0])[1] < mh:      # does not fill the screen -> stuck maximize
        print(c["address"]); break
' 2>/dev/null)"
    if [ -n "${stuck:-}" ]; then
      hyprctl dispatch focuswindow "address:$stuck" >/dev/null 2>&1
      hyprctl dispatch fullscreenstate 0 0 >/dev/null 2>&1
    fi
    { [ "$resmon" != "$mname" ] || [ "$reserved" != "$H" ]; } && set_reserve "$mname" "$H"
  else
    drop_reserve
  fi
  sleep "$POLL"
done
