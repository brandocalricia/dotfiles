#!/bin/bash
# Retired. The old copy armed a hardware watchdog and a passwordless reboot.
# Running this now only turns that off.
set -euo pipefail
exec bash /home/brandonrobertniehaus/dotfiles/scripts/unfreeze-disarm.sh
