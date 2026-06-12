#!/usr/bin/env bash
# Set wallpaper (+ regenerate the dynamic theme when it's active).
# Usage:
#   set-wallpaper.sh                # fuzzel picker over ~/Pictures/wallpapers
#   set-wallpaper.sh <image>        # set a specific image
#   set-wallpaper.sh --dynamic [im] # also switch INTO dynamic mode
# local.conf is untracked/per-machine: the swaybg exec-once line is updated
# in place so the choice survives relogin (contract documented in SETUP-NOTES).

set -eu
WALLS="$HOME/Pictures/wallpapers"
LOCAL_CONF="$HOME/.config/hypr/local.conf"

dynamic_requested=0
if [ "${1:-}" = "--dynamic" ] || [ "${1:-}" = "-d" ]; then
    dynamic_requested=1
    shift
fi

img="${1:-}"
if [ -z "$img" ]; then
    img=$(find "$WALLS" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -printf '%f\n' | sort | fuzzel --dmenu --prompt='Wallpaper: ') || exit 0
    img="$WALLS/$img"
fi
img=$(realpath "$img")
[ -f "$img" ] || { echo "no such image: $img" >&2; exit 1; }

# Persist into local.conf's swaybg exec-once line (create if missing)
if [ -f "$LOCAL_CONF" ] && grep -q '^exec-once = swaybg' "$LOCAL_CONF"; then
    sed -i "s|^exec-once = swaybg .*|exec-once = swaybg -i $img -m fill|" "$LOCAL_CONF"
else
    echo "exec-once = swaybg -i $img -m fill" >> "$LOCAL_CONF"
    echo "warn: appended swaybg line to $LOCAL_CONF (was missing)" >&2
fi

# Swap the running wallpaper
pkill -x swaybg 2>/dev/null || true
setsid swaybg -i "$img" -m fill >/dev/null 2>&1 < /dev/null &

# Dynamic mode: regenerate palette + reapply everything
current=$(cat "$HOME/.config/current-theme" 2>/dev/null || echo "")
if [ "$dynamic_requested" = 1 ] || [ "$current" = "dynamic" ]; then
    "$HOME/dotfiles/scripts/generate-dynamic-theme.sh" "$img"
    bash "$HOME/dotfiles/scripts/switch-theme.sh" dynamic
    notify-send 'Dynamic theme' "Recolored from $(basename "$img")"
    echo "greeter: run  sudo sh ~/dotfiles/scripts/greeter-apply.sh  to match the login screen"
fi
