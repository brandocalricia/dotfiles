#!/usr/bin/env bash
# install-auto-timezone.sh — wire up location-aware timezone on this host.
# Run as root:  sudo bash ~/dotfiles/scripts/install-auto-timezone.sh
# Idempotent — safe to re-run. Also invoked from the main install.sh.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run me as root:  sudo bash $0" >&2
  exit 1
fi

# Resolve the dotfiles root from this script's own location (survives sudo,
# which resets $HOME), so it works on any machine without extra args.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(dirname "$SCRIPT_DIR")"

echo "[+] Installing auto-timezone from $DOTFILES"

# 1. Detection script -> /usr/local/bin
install -m 0755 "$DOTFILES/scripts/auto-timezone.sh" /usr/local/bin/auto-timezone

# 2. systemd service + timer (system scope, needs root to set the clock)
install -m 0644 "$DOTFILES/systemd/system/auto-timezone.service" /etc/systemd/system/auto-timezone.service
install -m 0644 "$DOTFILES/systemd/system/auto-timezone.timer"   /etc/systemd/system/auto-timezone.timer

# 3. NetworkManager dispatcher hook (root:root 0755 or NM ignores it)
install -d -m 0755 /etc/NetworkManager/dispatcher.d
install -o root -g root -m 0755 "$DOTFILES/networkmanager/90-auto-timezone" \
  /etc/NetworkManager/dispatcher.d/90-auto-timezone

# 4. Hardware clock in UTC, not local time (systemd-recommended; fixes DST
#    and dual-boot clock skew). Harmless if already UTC.
timedatectl set-local-rtc 0 || true

# 5. Make sure NTP is running so the clock itself stays correct.
timedatectl set-ntp true || true

# 6. Enable the timer and run one detection pass right now.
systemctl daemon-reload
systemctl enable --now auto-timezone.timer
/usr/local/bin/auto-timezone || true

echo "[+] Done. Current state:"
timedatectl
