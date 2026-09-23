#!/usr/bin/env bash
# fedora only: keep hypridle on the Mac-like profile for the current power
# source (2 min battery / 10 min AC). Does nothing while caffeine is on.
# caffeine-toggle.sh sync owns the restart, including an 8s settle so a
# flickering port reading cannot reset the idle clock forever.
set -u
export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"

host="$(hostname -s 2>/dev/null || hostname)"
[[ "$host" == "fedora" ]] || exit 0

SYNC="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/caffeine-toggle.sh"

heal() { "$SYNC" sync >/dev/null 2>&1 || true; }

heal
while true; do
    if command -v upower >/dev/null 2>&1; then
        upower --monitor | while read -r _; do
            heal
        done
    else
        while sleep 5; do
            heal
        done
    fi
    sleep 2
done
