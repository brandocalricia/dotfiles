#!/usr/bin/env bash
# auto-timezone — set the system timezone from your PHYSICAL location, and never
# let a VPN drag it somewhere wrong.
#
# Strategy (in order):
#   1. WiFi geolocation via BeaconDB — your surrounding WiFi BSSIDs are physical,
#      so a VPN can't fake them. Only trusted on a REAL WiFi fix (BeaconDB's IP
#      fallback is rejected). VPN-proof wherever BeaconDB has coverage.
#   2. No WiFi fix + a VPN is up  -> leave the timezone UNCHANGED (hold the last
#      known-good physical zone rather than follow the VPN exit node).
#   3. No WiFi fix + no VPN       -> IP geolocation (physical when no VPN).
#
# Runs as root (timedatectl). Fired by auto-timezone.timer + a NetworkManager
# hook. Pure curl/jq/nmcli — no geoclue daemon, no extra services.
set -uo pipefail

log(){ logger -t auto-timezone -- "$*" 2>/dev/null || true; echo "auto-timezone: $*"; }

# ── Is a VPN tunnel currently up? ────────────────────────────────────────────
vpn_active(){
  ip -o link show up 2>/dev/null \
    | grep -qE ':\s+(nordlynx|tun[0-9]|tap[0-9]|wg[0-9]|proton[0-9]?|tailscale[0-9]|mullvad)' && return 0
  command -v nordvpn >/dev/null 2>&1 && nordvpn status 2>/dev/null | grep -qi 'Status: Connected' && return 0
  return 1
}

# ── Physical coordinates from nearby WiFi (BeaconDB); empty on IP-fallback ────
wifi_coords(){
  local aps resp
  aps=$(nmcli -t -f BSSID,SIGNAL dev wifi list 2>/dev/null | sed 's/\\:/:/g' \
        | awk -F: 'NF>=7 && $1!="" {printf "{\"macAddress\":\"%s:%s:%s:%s:%s:%s\",\"signalStrength\":%s},",$1,$2,$3,$4,$5,$6,$7}' \
        | sed 's/,$//')
  [ -z "$aps" ] && return 1
  resp=$(curl -fsS --max-time 12 -H 'Content-Type: application/json' \
         -d "{\"wifiAccessPoints\":[$aps]}" https://api.beacondb.net/v1/geolocate 2>/dev/null) || return 1
  # Reject IP fallback — we only trust a genuine WiFi fix here.
  printf '%s' "$resp" | jq -e 'has("fallback")' >/dev/null 2>&1 && return 1
  local lat lng
  lat=$(printf '%s' "$resp" | jq -r '.location.lat // empty' 2>/dev/null)
  lng=$(printf '%s' "$resp" | jq -r '.location.lng // empty' 2>/dev/null)
  [ -z "$lat" ] || [ -z "$lng" ] && return 1
  printf '%s %s\n' "$lat" "$lng"
}

# ── IANA timezone from coordinates (two keyless providers) ───────────────────
tz_from_coords(){
  local lat="$1" lng="$2" tz
  tz=$(curl -fsS --max-time 8 "https://timeapi.io/api/timezone/coordinate?latitude=$lat&longitude=$lng" 2>/dev/null \
        | jq -r '.timeZone // empty' 2>/dev/null) && [ -n "$tz" ] && { printf '%s\n' "$tz"; return 0; }
  tz=$(curl -fsS --max-time 8 "https://api.geotimezone.com/public/timezone?latitude=$lat&longitude=$lng" 2>/dev/null \
        | jq -r '.iana_timezone // empty' 2>/dev/null) && [ -n "$tz" ] && { printf '%s\n' "$tz"; return 0; }
  return 1
}

# ── IP-based timezone (physical only when no VPN) ────────────────────────────
tz_from_ip(){
  local tz
  tz=$(curl -fsS --max-time 8 https://ipapi.co/timezone/ 2>/dev/null) && [ -n "$tz" ] && { printf '%s\n' "$tz"; return 0; }
  tz=$(curl -fsS --max-time 8 "http://ip-api.com/line/?fields=timezone" 2>/dev/null) && [ -n "$tz" ] && { printf '%s\n' "$tz"; return 0; }
  return 1
}

# ── Decide the timezone ──────────────────────────────────────────────────────
new_tz=""; src=""
if coords=$(wifi_coords); then
  if new_tz=$(tz_from_coords $coords); then src="WiFi fix ($coords)"; fi
fi
if [ -z "$new_tz" ]; then
  if vpn_active; then
    log "no WiFi fix and VPN active — holding current timezone (won't follow the VPN)"
    exit 0
  fi
  new_tz=$(tz_from_ip) && src="IP geolocation (no VPN)"
fi

new_tz=${new_tz//[$'\r\n\t ']/}
if [ -z "$new_tz" ]; then log "could not determine timezone (offline?)"; exit 0; fi
if [ ! -e "/usr/share/zoneinfo/$new_tz" ]; then log "invalid zone '$new_tz', ignoring"; exit 0; fi

cur_tz=$(timedatectl show -p Timezone --value)
if [ "$new_tz" = "$cur_tz" ]; then log "timezone already correct ($cur_tz) [$src]"; exit 0; fi

timedatectl set-timezone "$new_tz"
log "timezone changed: $cur_tz -> $new_tz [$src]"

if command -v notify-send >/dev/null 2>&1; then
  for bus in /run/user/*/bus; do
    uid=$(basename "$(dirname "$bus")")
    sudo -u "#$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      notify-send "🕐 Timezone updated" "Now $new_tz" 2>/dev/null || true
  done
fi
