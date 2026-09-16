#!/usr/bin/env bash
# Install the Brave/NordVPN color-icon font, then start waybar.
# Hyprland exec-once points here so the font is in fontconfig before the bar draws.
set -u
src="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/fonts/waybar-app-icons.ttf"
dst="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/waybar-app-icons.ttf"
if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    if ! cmp -s "$src" "$dst" 2>/dev/null; then
        cp -f "$src" "$dst"
        fc-cache -f "$(dirname "$dst")" >/dev/null 2>&1 || true
    fi
fi
exec waybar "$@"
