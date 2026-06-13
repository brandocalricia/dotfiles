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

# Persist into local.conf's 'swww img' exec-once line (the path is what we
# sed; --transition-type none keeps login instant). Append if missing.
if [ -f "$LOCAL_CONF" ] && grep -q '^exec-once = sleep .* swww img' "$LOCAL_CONF"; then
    sed -i "s|^exec-once = sleep .* swww img .*|exec-once = sleep 1 \&\& swww img $img --transition-type none|" "$LOCAL_CONF"
else
    { echo "exec-once = swww-daemon"
      echo "exec-once = sleep 1 && swww img $img --transition-type none"; } >> "$LOCAL_CONF"
    echo "warn: appended swww exec-once lines to $LOCAL_CONF (were missing)" >&2
fi

# Swap the running wallpaper with an animated transition. Ensure daemon is up.
if ! swww query >/dev/null 2>&1; then
    setsid swww-daemon >/dev/null 2>&1 < /dev/null &
    for _ in 1 2 3 4 5 6 7 8 9 10; do swww query >/dev/null 2>&1 && break; sleep 0.2; done
fi
swww img "$img" --transition-type grow --transition-fps 60 --transition-duration 1.2 || \
    echo "warn: swww img failed (daemon not ready?)" >&2

# Dynamic mode: regenerate palette + reapply everything
current=$(cat "$HOME/.config/current-theme" 2>/dev/null || echo "")
if [ "$dynamic_requested" = 1 ] || [ "$current" = "dynamic" ]; then
    "$HOME/dotfiles/scripts/generate-dynamic-theme.sh" "$img"
    bash "$HOME/dotfiles/scripts/switch-theme.sh" dynamic
    notify-send 'Dynamic theme' "Recolored from $(basename "$img")"
    echo "greeter: run  sudo sh ~/dotfiles/scripts/greeter-apply.sh  to match the login screen"
fi
