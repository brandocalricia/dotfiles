#!/usr/bin/env bash
# auto-update.sh — low-risk unattended updates, run by auto-update.timer (root).
#
# Philosophy: never surprise-break a running system.
#   1. Take a snapper snapshot first (guaranteed rollback point).
#   2. Download ALL pending updates (stages them; zero system change) so a
#      later manual `sudo dnf upgrade` is instant.
#   3. Apply only SECURITY advisories automatically (low churn, high value).
#      Kernel/security updates don't affect the running kernel until reboot.
#   4. Update Flatpaks.
# Full feature upgrades stay a deliberate manual `sudo dnf upgrade`.
# Every dnf call carries --exclude=gdm (a GDM install once locked the user out).
set -uo pipefail

log(){ logger -t auto-update -- "$*" 2>/dev/null || true; echo "auto-update: $*"; }

log "starting"

# 1. Rollback point (best-effort; harmless if snapper/root config absent).
if command -v snapper >/dev/null 2>&1; then
  snapper create -d "pre auto-update $(date -Iseconds)" 2>/dev/null \
    && log "snapper pre-snapshot created" || log "snapper snapshot skipped"
fi

# 2. Stage every pending update (no install).
dnf -y --refresh --exclude=gdm upgrade --downloadonly 2>&1 | tail -5 \
  && log "all updates downloaded (staged)" || log "download step had issues"

# 3. Apply security advisories only.
if dnf -y --exclude=gdm upgrade --security 2>&1 | tail -8; then
  log "security updates applied"
else
  log "no security updates / apply skipped"
fi

# 4. Flatpaks (low risk, sandboxed).
if command -v flatpak >/dev/null 2>&1; then
  flatpak update -y --noninteractive 2>&1 | tail -5 || true
  log "flatpak updated"
fi

# 5. Nudge the desktop if any non-security updates are still staged.
staged=$(dnf -q --cacheonly list --upgrades 2>/dev/null | grep -c . || true)
if [[ "${staged:-0}" -gt 0 ]] && command -v notify-send >/dev/null 2>&1; then
  for bus in /run/user/*/bus; do
    uid=$(basename "$(dirname "$bus")")
    sudo -u "#$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=$bus" \
      notify-send "⬆️ Updates staged" "Feature updates downloaded — run: sudo dnf upgrade" 2>/dev/null || true
  done
fi

log "done"
