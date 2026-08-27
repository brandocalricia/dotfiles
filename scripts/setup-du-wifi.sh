#!/usr/bin/env bash
# setup-du-wifi.sh — one-shot NetworkManager profile for DU campus WiFi (eduroam).
#
# WHY: Hyprland has no GNOME/KDE WiFi wizard. nmtui is fine for home/airport
# WPA-PSK, but eduroam is WPA-Enterprise (PEAP/MSCHAPv2) and nmtui will not
# prompt for those EAP fields on first activate — you get "connected" or a
# silent fail. There is also no NM secret-agent on this setup (no nm-applet /
# gnome-keyring), so the password MUST be stored in the profile.
#
# This is NOT the airport login-page issue. That is captive-portal-watch.sh
# (hotels / airports / DU Guest). Students should use eduroam.
# DU IT: https://www.du.edu/it/services/networks-internet/wireless-wired
# Username = full DU email. DU is not on cat.eduroam.org, so no official
# Linux installer — this is the manual equivalent.
#
# Safe to re-run (updates the existing profile). Does not need the campus
# SSID in range — create it at home, it auto-connects when you arrive.
# Usage: bash ~/dotfiles/scripts/setup-du-wifi.sh
set -euo pipefail

CON_NAME="eduroam"
SSID="eduroam"
CA_BUNDLE="/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem"

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!  %s\n' "$*" >&2; }

if ! command -v nmcli >/dev/null 2>&1; then
  warn "nmcli not found — NetworkManager is required"
  exit 1
fi

printf 'DU eduroam setup\n'
printf 'Use your full University of Denver email (the one you use for PioneerWeb).\n'
printf 'Identity (email): '
IFS= read -r identity
if [ -z "${identity}" ] || [ "${identity}" = "${identity%%@*}" ]; then
  warn "That doesn't look like an email. DU wants the full address, e.g. first.last@du.edu"
  exit 1
fi

printf 'Password (input hidden): '
IFS= read -rs password
printf '\n'
if [ -z "${password}" ]; then
  warn "empty password — aborting"
  exit 1
fi

common=(
  wifi.ssid "$SSID"
  wifi.mode infrastructure
  wifi.cloned-mac-address permanent
  wifi-sec.key-mgmt wpa-eap
  802-1x.eap peap
  802-1x.phase2-auth mschapv2
  802-1x.identity "$identity"
  802-1x.password "$password"
  802-1x.password-flags 0
  802-1x.system-ca-certs yes
  connection.autoconnect yes
  connection.autoconnect-priority 100
)

if [ -f "$CA_BUNDLE" ]; then
  common+=(802-1x.ca-cert "$CA_BUNDLE")
fi

if nmcli -t -f NAME connection show | grep -Fxq "$CON_NAME"; then
  log "Updating existing '$CON_NAME' profile"
  nmcli connection modify "$CON_NAME" "${common[@]}"
else
  log "Creating '$CON_NAME' profile"
  nmcli connection add type wifi con-name "$CON_NAME" ssid "$SSID" "${common[@]}"
fi

# Drop the password from this shell as soon as NM has it.
unset password

log "Saved. On campus: click the waybar wifi module → Activate '$CON_NAME',"
log "or it should auto-connect when the SSID is in range."
log "If it associates but never gets an IP, the TLS-1.3 fallback is:"
log "  nmcli connection modify $CON_NAME 802-1x.phase1-auth-flags tls-1-3-disable"
log "  nmcli connection up $CON_NAME"
log "Guest/event WiFi is a different network (DU Guest) — that's the login-page"
log "popup, handled automatically. Right-click the waybar wifi module to force it."
