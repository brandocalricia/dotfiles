#!/usr/bin/env bash
# Start hypridle with this host's idle profile.
# Laptop `fedora`: MacBook-matching timers, battery vs AC.
# Desktop and anything else: ~/.config/hypr/hypridle.conf (5 min blank/lock, 15 min sleep).
set -u
export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
host="$(hostname -s 2>/dev/null || hostname)"

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

if [[ "$host" == "fedora" ]]; then
    if on_ac; then
        conf="${CONF_DIR}/hypridle.fedora-ac.conf"
    else
        conf="${CONF_DIR}/hypridle.fedora-battery.conf"
    fi
    [[ -f "$conf" ]] || conf="${CONF_DIR}/hypridle.conf"
    exec hypridle -c "$conf" "$@"
fi

exec hypridle "$@"
