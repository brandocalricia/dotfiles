#!/bin/bash
# Turn off the automatic reboot installed earlier. Does not reboot.
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo "run as root" >&2
  exit 1
fi
rm -f /etc/sudoers.d/unfreeze-reboot
rm -f /etc/systemd/system.conf.d/99-watchdog.conf
install -m 755 /home/brandonrobertniehaus/dotfiles/scripts/unfreeze-reboot /usr/local/sbin/unfreeze-reboot
# Apply the removed watchdog drop-in. This re-executes pid 1; it does not reboot.
systemctl daemon-reexec
echo "sysrq=$(cat /proc/sys/kernel/sysrq)"
systemctl show -p RuntimeWatchdogSec -p RebootWatchdogSec -p WatchdogLastPingTimestamp
