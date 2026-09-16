#!/usr/bin/env bash
# fedora only: when AC is plugged/unplugged, restart hypridle onto the matching
# Mac-like profile (2 min battery / 10 min AC). Does nothing while caffeine is on.
set -u
export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"

CAFFEINE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.on"
RUNNER="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/run-hypridle.sh"

on_ac() {
    local d online st
    for d in /sys/class/power_supply/*/type; do
        [[ -f "$d" ]] || continue
        if [[ "$(cat "$d" 2>/dev/null)" == "Mains" ]]; then
            online="${d%/type}/online"
            [[ -f "$online" && "$(cat "$online" 2>/dev/null)" == "1" ]] && return 0
        fi
    done
    st="$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || true)"
    case "$st" in
        Charging|Full) return 0 ;;
    esac
    return 1
}

source_label() {
    if on_ac; then echo ac; else echo battery; fi
}

reload_hypridle() {
    [[ -f "$CAFFEINE" ]] && return 0
    pkill -x hypridle 2>/dev/null || true
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch exec "$RUNNER" >/dev/null 2>&1
    else
        setsid -f "$RUNNER" >/dev/null 2>&1
    fi
}

prev="$(source_label)"
if command -v upower >/dev/null 2>&1; then
    upower --monitor | while read -r _; do
        now="$(source_label)"
        if [[ "$now" != "$prev" ]]; then
            prev="$now"
            reload_hypridle
        fi
    done
else
    while sleep 2; do
        now="$(source_label)"
        if [[ "$now" != "$prev" ]]; then
            prev="$now"
            reload_hypridle
        fi
    done
fi
