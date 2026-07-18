#!/usr/bin/env bash
# Caffeine toggle for hypridle (kill / relaunch).
#
# Caffeine ON  -> hypridle is killed, so NO idle timers exist: display never blanks,
#                 no auto-lock, no auto-suspend.
# Caffeine OFF -> a fresh hypridle is launched (via hyprctl dispatch exec, so it gets
#                 a clean Wayland connection in the real session env) and normal idle
#                 behavior resumes.
#
# Why kill/relaunch instead of SIGSTOP/SIGCONT: freezing hypridle for a long time made
# Hyprland drop its Wayland connection (unanswered pings), so on resume it was alive but
# deaf to idle events and the screen never blanked again. Killing avoids that entirely.
#
# State for the Waybar readout is tracked in an explicit file so the display is correct
# regardless of the minimal env Waybar launches the script in.
#
# Usage:
#   caffeine-toggle.sh          -> flip state (bound to Waybar on-click)
#   caffeine-toggle.sh status   -> print Waybar JSON for the current state
#   caffeine-toggle.sh on|off   -> force a state
#   caffeine-toggle.sh sync     -> make reality match the state file (self-heal)

# Harden PATH: Waybar is launched from Hyprland's exec-once with a minimal environment,
# where pkill/pidof/hyprctl may not otherwise be found.
export PATH="/usr/bin:/bin:/usr/local/bin:$PATH"

set -uo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/caffeine.on"

is_on() { [[ -f "$STATE_FILE" ]]; }
hypridle_running() { pidof hypridle >/dev/null 2>&1; }

start_hypridle() {
    hypridle_running && return 0
    # Prefer hyprctl so hypridle spawns in Hyprland's session env with a clean
    # Wayland connection; fall back to a detached launch if hyprctl is unavailable.
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl dispatch exec hypridle >/dev/null 2>&1
    else
        setsid -f hypridle >/dev/null 2>&1
    fi
}

caffeine_on() {
    : > "$STATE_FILE"
    pkill -x hypridle 2>/dev/null || true
}

caffeine_off() {
    rm -f "$STATE_FILE"
    start_hypridle
}

# Make the running daemon match the state file (recover from a bad state).
sync_state() {
    if is_on; then
        pkill -x hypridle 2>/dev/null || true
    else
        start_hypridle
    fi
}

print_status() {
    if is_on; then
        printf '{"text":"󰅶","tooltip":"Caffeine ON","class":"active","alt":"on"}\n'
    else
        printf '{"text":"󰾯","tooltip":"Caffeine OFF","class":"inactive","alt":"off"}\n'
    fi
}

case "${1:-toggle}" in
    on)     caffeine_on ;;
    off)    caffeine_off ;;
    sync)   sync_state ;;
    status) print_status; exit 0 ;;
    toggle|*)
        if is_on; then caffeine_off; else caffeine_on; fi
        ;;
esac

# After a state change, tell Waybar to refresh the module immediately.
pkill -RTMIN+9 -x waybar 2>/dev/null || true
