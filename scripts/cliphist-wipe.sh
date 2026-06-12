#!/usr/bin/env bash
# Clear cliphist clipboard history after a fuzzel confirmation.
# Bound to Super+Shift+V in hyprland.conf.

choice=$(printf 'No\nYes — wipe history' | fuzzel --dmenu --prompt='Wipe clipboard history? ' --lines=2)
if [[ "$choice" == Yes* ]]; then
    cliphist wipe
    notify-send 'Clipboard' 'History cleared'
fi
