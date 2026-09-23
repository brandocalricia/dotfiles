#!/usr/bin/env bash
# Caffeine toggle for hypridle (kill / relaunch).
#
# Caffeine ON  -> hypridle is killed, so NO idle timers exist: display never blanks,
#                 no auto-lock, no auto-suspend.
# Caffeine OFF -> one hypridle is running on this host's current profile
#                 (fedora: battery 2 min / AC 10 min, after a short settle).
#
# Why kill/relaunch instead of SIGSTOP/SIGCONT: freezing hypridle for a long time made
# Hyprland drop its Wayland connection (unanswered pings), so on resume it was alive but
# deaf to idle events and the screen never blanked again. Killing avoids that entirely.
#
# `status` (Waybar, every few seconds) and `sync` heal a dead daemon or a daemon
# stuck on the other power profile. The state file alone used to say "off" while
# hypridle kept running the plugged-in timers on battery.
#
# Usage:
#   caffeine-toggle.sh          -> flip state (bound to Waybar on-click)
#   caffeine-toggle.sh status   -> heal, then print Waybar JSON
#   caffeine-toggle.sh on|off   -> force a state
#   caffeine-toggle.sh sync     -> make reality match the state file

# Harden PATH: Waybar is launched from Hyprland's exec-once with a minimal environment,
# where pkill/pidof/hyprctl may not otherwise be found.
export PATH="/usr/bin:/bin:/usr/local/bin:$PATH"

set -uo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.on"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/hypridle-ctl.lock"
HYPRIDLE_LAUNCH="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/run-hypridle.sh"

is_on() { [[ -f "$STATE_FILE" ]]; }

hypridle_pids() {
    local line
    line="$(pidof hypridle 2>/dev/null || true)"
    [[ -n "$line" ]] || return 0
    # shellcheck disable=SC2086
    printf '%s\n' $line
}

hypridle_running() { hypridle_pids | grep -q .; }

# Config path of the first hypridle, if it was started with -c / --config.
current_hypridle_config() {
    local pid args=() a i
    pid="$(hypridle_pids | head -n 1)"
    [[ -n "$pid" && -r "/proc/$pid/cmdline" ]] || return 1
    while IFS= read -r -d '' a; do
        args+=("$a")
    done < "/proc/$pid/cmdline"
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" == "-c" || "${args[$i]}" == "--config" ]]; then
            printf '%s\n' "${args[$((i + 1))]:-}"
            return 0
        fi
    done
    return 1
}

wait_hypridle_dead() {
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        hypridle_running || return 0
        sleep 0.1
    done
}

start_hypridle() {
    local conf="$1"
    [[ -f "$conf" ]] || return 1
    hypridle_running && return 0
    # Prefer hyprctl so hypridle spawns in Hyprland's session env with a clean
    # Wayland connection; fall back to a detached launch if hyprctl is unavailable.
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch exec "$HYPRIDLE_LAUNCH --config $conf" >/dev/null 2>&1
    else
        setsid -f "$HYPRIDLE_LAUNCH" --config "$conf" >/dev/null 2>&1
    fi
    local _
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        hypridle_running && return 0
        sleep 0.1
    done
    return 1
}

# Caller holds LOCK_FILE.
apply_locked() {
    local want have count
    if is_on; then
        if hypridle_running; then
            pkill -x hypridle 2>/dev/null || true
            wait_hypridle_dead
        fi
        return 0
    fi

    want="$("$HYPRIDLE_LAUNCH" --print-config 2>/dev/null || true)"
    [[ -n "$want" && -f "$want" ]] || return 1
    have="$(current_hypridle_config || true)"
    count="$(hypridle_pids | wc -l)"

    if [[ "$count" -eq 1 && "$have" == "$want" ]]; then
        return 0
    fi

    if hypridle_running; then
        pkill -x hypridle 2>/dev/null || true
        wait_hypridle_dead
    fi
    start_hypridle "$want"
}

sync_state() {
    (
        flock 9 || exit 1
        apply_locked
    ) 9>"$LOCK_FILE"
}

caffeine_on() { : > "$STATE_FILE"; }
caffeine_off() { rm -f "$STATE_FILE"; }

print_status() {
    # Same cup both states; ON/off label + CSS chip carry the meaning.
    local tip conf
    if is_on; then
        printf '{"text":"󰛊  ON","tooltip":"Caffeine ON — idle timers paused (no blank/lock/suspend)","class":"active","alt":"on"}\n'
        return 0
    fi
    if hypridle_running; then
        conf="$(current_hypridle_config || true)"
        case "$conf" in
            *fedora-battery*)
                tip="Caffeine off — on battery, display sleeps at 2 min"
                ;;
            *fedora-ac*)
                tip="Caffeine off — on power, display sleeps at 10 min"
                ;;
            *)
                tip="Caffeine off — idle timers running"
                ;;
        esac
    else
        tip="Caffeine off — idle daemon is down, retrying"
    fi
    printf '{"text":"󰛊  off","tooltip":"%s","class":"inactive","alt":"off"}\n' "$tip"
}

case "${1:-toggle}" in
    on)     caffeine_on; sync_state ;;
    off)    caffeine_off; sync_state ;;
    sync)   sync_state; exit 0 ;;
    status) sync_state; print_status; exit 0 ;;
    toggle|*)
        if is_on; then caffeine_off; else caffeine_on; fi
        sync_state
        ;;
esac

# After a user toggle, tell Waybar to refresh the module immediately.
# sync/status must not signal: status is what Waybar runs, and the power
# watcher calls sync on every upower line.
pkill -RTMIN+9 -x waybar 2>/dev/null || true
