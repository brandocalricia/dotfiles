#!/usr/bin/env bash
# Screenshot pipeline. Usage: screenshot.sh <full|region|annotate>
#   full     — entire screen -> clipboard + file (Print)
#   region   — selection -> clipboard only (Super+Shift+S)
#   annotate — region -> satty -> clipboard + file (Super+Print)
#
# grim must finish and close its Wayland connection before wl-copy opens
# one. A grim|wl-copy pipe deadlocks Hyprland: every client stops painting
# and only a TTY still responds.
set -eu
dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"
copy="$HOME/dotfiles/scripts/wl-copy-detach.sh"

copy_png() {
  "$copy" image/png < "$1"
}

case "${1:-}" in
  full)
    timeout --foreground 8 grim "$f"
    if copy_png "$f"; then
      notify-send 'Screenshot' "Saved + copied: ${f##*/}"
    else
      notify-send 'Screenshot' "Saved (clipboard timed out): ${f##*/}"
    fi
    ;;
  region)
    geom=$(slurp) || exit 0
    [ -n "$geom" ] || exit 0
    tmp=$(mktemp /tmp/shot.XXXXXX.png)
    trap 'rm -f "$tmp"' EXIT
    timeout --foreground 8 grim -g "$geom" "$tmp"
    copy_png "$tmp"
    notify-send 'Screenshot' 'Region copied'
    ;;
  annotate)
    geom=$(slurp) || exit 0
    [ -n "$geom" ] || exit 0
    timeout --foreground 8 grim -g "$geom" - | satty --filename - \
      --output-filename "$f" \
      --copy-command "$copy" \
      --actions-on-enter save-to-clipboard \
      --actions-on-enter save-to-file \
      --actions-on-enter exit \
      --early-exit
    [[ -f "$f" ]] && notify-send 'Screenshot' "Annotated: ${f##*/}"
    ;;
  *)
    echo "usage: $0 <full|region|annotate>" >&2
    exit 1
    ;;
esac
