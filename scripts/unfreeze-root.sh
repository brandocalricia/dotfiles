#!/bin/bash
# One-time root setup for desktop-freeze recovery. Idempotent.
#   sudo bash ~/dotfiles/scripts/unfreeze-root.sh
# Does not touch the display manager, PAM, or gdm.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo bash $0" >&2
  exit 1
fi

install -d -m 755 /etc/sysctl.d /etc/systemd/system.conf.d /usr/local/sbin /etc/sudoers.d
cat > /etc/sysctl.d/99-sysrq.conf << 'EOF'
# Alt+PrintScreen, then r e i s u b, can recover a dead GUI.
kernel.sysrq = 1
EOF
sysctl -w kernel.sysrq=1 >/dev/null

cat > /etc/systemd/system.conf.d/99-watchdog.conf << 'EOF'
[Manager]
# If pid 1 stops petting the hardware watchdog, reboot. Covers a hard
# lock where userspace recovery cannot run. Suspend disarms this.
RuntimeWatchdogSec=120s
RebootWatchdogSec=3min
EOF

install -m 755 /home/brandonrobertniehaus/dotfiles/scripts/unfreeze-reboot /usr/local/sbin/unfreeze-reboot

user="${SUDO_USER:-}"
if [ -z "$user" ] && [ -n "${PKEXEC_UID:-}" ]; then
  user=$(id -nu "$PKEXEC_UID")
fi
if [ -z "$user" ]; then
  user=brandonrobertniehaus
fi
tmp=$(mktemp)
printf '%s ALL=(root) NOPASSWD: /usr/local/sbin/unfreeze-reboot\n' "$user" > "$tmp"
visudo -cf "$tmp"
install -m 440 "$tmp" /etc/sudoers.d/unfreeze-reboot
rm -f "$tmp"

systemctl daemon-reexec
echo "sysrq=$(cat /proc/sys/kernel/sysrq)"
systemctl show -p RuntimeWatchdogSec -p RebootWatchdogSec
