#!/usr/bin/env bash
# auto-timezone — set the system timezone from IP geolocation.
#
# Runs as root (needs `timedatectl set-timezone`). Fired by:
#   • auto-timezone.timer            — on boot + hourly
#   • NetworkManager dispatcher hook — the moment a connection comes up
# so the clock follows you as you travel, without any GUI toggle.
#
# Pure curl + coreutils: no Python/Rust deps, so it ports 1:1 to any host.
set -euo pipefail

log() { logger -t auto-timezone -- "$*" 2>/dev/null || true; echo "auto-timezone: $*"; }

# Query providers in order; first one to return a non-empty IANA zone wins.
# All are keyless and return the zone as plain text.
fetch_tz() {
  local tz
  tz=$(curl -fsS --max-time 8 https://ipapi.co/timezone/ 2>/dev/null) \
    && [[ -n $tz ]] && { printf '%s\n' "$tz"; return 0; }
  tz=$(curl -fsS --max-time 8 "http://ip-api.com/line/?fields=timezone" 2>/dev/null) \
    && [[ -n $tz ]] && { printf '%s\n' "$tz"; return 0; }
  tz=$(curl -fsS --max-time 8 https://ipwho.is/ 2>/dev/null \
        | grep -oP '"timezone":\{[^}]*"id":"\K[^"]+') \
    && [[ -n $tz ]] && { printf '%s\n' "$tz"; return 0; }
  return 1
}

new_tz=$(fetch_tz) || { log "could not determine timezone (offline / providers down)"; exit 0; }
new_tz=${new_tz//[$'\r\n\t ']/}   # strip any stray whitespace

# Never touch the clock on a bogus value — only accept real zoneinfo entries.
if [[ -z $new_tz || ! -e "/usr/share/zoneinfo/$new_tz" ]]; then
  log "provider returned invalid zone '${new_tz:-<empty>}', ignoring"
  exit 0
fi

cur_tz=$(timedatectl show -p Timezone --value)
if [[ $new_tz == "$cur_tz" ]]; then
  log "timezone already correct ($cur_tz)"
  exit 0
fi

timedatectl set-timezone "$new_tz"
log "timezone changed: $cur_tz -> $new_tz"

# Best-effort desktop toast so a running session notices the jump.
if command -v notify-send >/dev/null 2>&1; then
  for bus in /run/user/*/bus; do
    uid=$(basename "$(dirname "$bus")")
    sudo -u "#$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      notify-send "🕐 Timezone updated" "Now $new_tz" 2>/dev/null || true
  done
fi
