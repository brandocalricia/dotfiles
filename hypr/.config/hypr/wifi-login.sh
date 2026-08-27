#!/usr/bin/env bash
# wifi-login.sh — manual captive-portal trigger for Hyprland.
#
# The automatic agent is captive-portal-watch.sh (exec-once). Use this when
# you're "connected" with no internet and the popup didn't fire (some
# gateways don't trip NM's portal state). Same probe URL the watcher uses.
# Bound to waybar network module right-click.
set -uo pipefail
PROBE_URL="http://neverssl.com"
notify-send -u critical -i network-wireless-signal-good \
  "WiFi login" "Opening a page that should bounce you to the sign-in screen…" 2>/dev/null || true
setsid xdg-open "$PROBE_URL" >/dev/null 2>&1 < /dev/null &
