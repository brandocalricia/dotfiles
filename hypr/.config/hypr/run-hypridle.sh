#!/usr/bin/env bash
# Start hypridle with this host's idle profile.
# Laptop `fedora`: MacBook-matching timers, battery vs AC.
# Desktop and anything else: ~/.config/hypr/hypridle.conf (5 min blank/lock, 15 min sleep).
#
#   run-hypridle.sh                 exec hypridle on the stable profile
#   run-hypridle.sh --print-config  print the config path hypridle should use
#   run-hypridle.sh --config PATH   exec hypridle on PATH (no new power read)
set -u
export PATH="/usr/bin:/bin:/usr/local/bin:${PATH}"

CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
host="$(hostname -s 2>/dev/null || hostname)"
# A port that flickers for a few seconds must not restart hypridle. Each
# restart clears the idle clock, so a flap means the screen never sleeps.
SETTLE_SEC=8
POWER_STATE="${XDG_RUNTIME_DIR:-/tmp}/hypridle-power.source"

on_ac() {
    local d online st typ
    for d in /sys/class/power_supply/*/type; do
        [[ -f "$d" ]] || continue
        typ="$(cat "$d" 2>/dev/null || true)"
        # Framework USB-C PD shows up as type USB (ucsi-source-psy), not Mains.
        case "$typ" in
            Mains|USB) ;;
            *) continue ;;
        esac
        online="${d%/type}/online"
        [[ -f "$online" && "$(cat "$online" 2>/dev/null)" == "1" ]] && return 0
    done
    st="$(cat /sys/class/power_supply/BAT1/status 2>/dev/null || true)"
    case "$st" in
        Charging|Full) return 0 ;;
    esac
    return 1
}

# Echo "ac" or "battery". The first sample commits immediately. A later change
# commits only after SETTLE_SEC of the new reading.
stable_source() {
    local live now committed pending since tmp
    if on_ac; then live=ac; else live=battery; fi
    now=$(date +%s)
    tmp="${POWER_STATE}.tmp"

    if [[ ! -s "$POWER_STATE" ]]; then
        printf '%s -\n' "$live" > "$tmp"
        mv -f "$tmp" "$POWER_STATE"
        echo "$live"
        return
    fi

    read -r committed pending since < "$POWER_STATE" || true
    [[ -n "${committed:-}" ]] || committed=$live

    if [[ "$live" == "$committed" ]]; then
        printf '%s -\n' "$committed" > "$tmp"
        mv -f "$tmp" "$POWER_STATE"
        echo "$committed"
        return
    fi

    if [[ "$pending" == "$live" && "$since" =~ ^[0-9]+$ ]] && (( now - since >= SETTLE_SEC )); then
        printf '%s -\n' "$live" > "$tmp"
        mv -f "$tmp" "$POWER_STATE"
        echo "$live"
        return
    fi

    if [[ "$pending" != "$live" ]]; then
        printf '%s %s %s\n' "$committed" "$live" "$now" > "$tmp"
        mv -f "$tmp" "$POWER_STATE"
    fi
    echo "$committed"
}

resolve_config() {
    local src conf
    if [[ "$host" != "fedora" ]]; then
        echo "${CONF_DIR}/hypridle.conf"
        return
    fi
    src="$(stable_source)"
    if [[ "$src" == "ac" ]]; then
        conf="${CONF_DIR}/hypridle.fedora-ac.conf"
    else
        conf="${CONF_DIR}/hypridle.fedora-battery.conf"
    fi
    [[ -f "$conf" ]] || conf="${CONF_DIR}/hypridle.conf"
    echo "$conf"
}

case "${1:-}" in
    --print-config)
        resolve_config
        exit 0
        ;;
    --config)
        [[ -n "${2:-}" && -f "$2" ]] || exit 1
        exec hypridle -c "$2"
        ;;
esac

exec hypridle -c "$(resolve_config)"
