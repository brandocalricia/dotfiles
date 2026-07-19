#!/usr/bin/env bash
# captive-portal-watch.sh — the "airport WiFi login page" popup for Hyprland.
#
# WHY THIS EXISTS: macOS/iOS/GNOME/KDE ship a background agent that watches
# NetworkManager's connectivity state and, the moment it sees a *captive portal*
# (WiFi says "connected" but the internet is gated behind a login page — hotels,
# airports, campus WiFi like DU), pops that login page open for you. Hyprland is
# a bare compositor with NO such agent, so NM detects the portal but nobody shows
# you the page → you sit there "connected" with no internet and no popup. This
# script IS that agent: on a transition into `portal`, it opens the login page in
# your browser and fires a notification.
#
# NM already does the detection (NetworkManager-config-connectivity-fedora ships
# the connectivity check, `nmcli networking connectivity` → full|portal|none).
# We only add the missing "open the page" reaction. No sudo, no daemon config.
#
# Launched once per session from hyprland.conf:  exec-once = ~/.config/hypr/captive-portal-watch.sh
#
# Testing hooks (see README in the repo / Sessions note):
#   CAPTIVE_PORTAL_DRYRUN=1  → log the intended action instead of opening a
#                              browser / sending a notification (so the full
#                              detection→action path can be proven without
#                              spawning a GUI app on the live session).
#   CAPTIVE_PORTAL_LOG=<path> → where dry-run/diagnostic lines go
#                               (default: $XDG_RUNTIME_DIR/captive-portal-watch.log).
set -uo pipefail

# A plain-HTTP URL that never upgrades to HTTPS — the community-standard captive
# portal trigger. Behind a portal, the gateway hijacks this request and serves
# its login page; with real internet it just loads a tiny page. (We deliberately
# do NOT hardcode the portal's own URL — it's unknown until the gateway redirects.)
PROBE_URL="http://neverssl.com"

LOG="${CAPTIVE_PORTAL_LOG:-${XDG_RUNTIME_DIR:-/tmp}/captive-portal-watch.log}"

log() { printf '%s %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo '--:--:--')" "$*" >> "$LOG" 2>/dev/null || true; }

# Singleton via flock: hold an exclusive lock for our whole lifetime. Both the
# Hyprland exec-once AND the dotfiles-sync self-heal may try to launch us, so a
# second instance must be harmless — it fails the lock and exits immediately.
# This makes "launch unconditionally" safe and prevents duplicate browsers on a
# real portal. (Skipped when CAPTIVE_PORTAL_LOCK=none, e.g. unit tests.)
if [ "${CAPTIVE_PORTAL_LOCK:-}" != "none" ] && command -v flock >/dev/null 2>&1; then
  exec 9>"${XDG_RUNTIME_DIR:-/tmp}/captive-portal-watch.lock" 2>/dev/null || true
  flock -n 9 || { log "another instance holds the lock — exiting"; exit 0; }
fi

open_portal() {
  if [ -n "${CAPTIVE_PORTAL_DRYRUN:-}" ]; then
    log "DRYRUN portal detected → would notify + open $PROBE_URL"
    return 0
  fi
  log "portal detected → opening $PROBE_URL"
  notify-send -u critical -i network-wireless-signal-good \
    "WiFi login required" "Opening the network's sign-in page…" 2>/dev/null || true
  # Open in the default browser; the captive gateway redirects it to the real
  # login page. Backgrounded + detached so this watcher keeps running.
  setsid xdg-open "$PROBE_URL" >/dev/null 2>&1 < /dev/null &
}

last=""
handle() {
  local state="$1"
  [ -z "$state" ] && return 0
  if [ "$state" = "portal" ] && [ "$last" != "portal" ]; then
    open_portal
  fi
  [ "$state" != "$last" ] && log "connectivity: ${last:-<start>} → $state"
  last="$state"
}

# Seed with the current state, in case we log in already behind a portal.
handle "$(nmcli networking connectivity 2>/dev/null)"

# Stream connectivity changes forever. If `nmcli monitor` ever dies (e.g. NM
# restarts), restart it after a short pause so the watcher self-heals.
while true; do
  nmcli monitor 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      *"Connectivity is now"*)
        # Line looks like:  Connectivity is now 'portal' — pull out the quoted word.
        state="${line#*\'}"; state="${state%\'*}"
        handle "$state"
        ;;
    esac
  done
  log "nmcli monitor exited — restarting in 3s"
  sleep 3
done
