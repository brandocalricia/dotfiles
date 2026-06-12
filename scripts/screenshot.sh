#!/usr/bin/env bash
# Screenshot pipeline. Usage: screenshot.sh <full|annotate>
#   full     — entire screen -> clipboard + file (Print)
#   annotate — region -> satty -> clipboard + file (Super+Print)
# Plain fast region->clipboard stays a raw grim|wl-copy bind (Super+Shift+S).

set -eu
dir="$HOME/Pictures/screenshots"
mkdir -p "$dir"
f="$dir/$(date +%Y-%m-%d_%H-%M-%S).png"

case "${1:-}" in
    full)
        grim "$f"
        wl-copy < "$f"
        notify-send 'Screenshot' "Saved + copied: ${f##*/}"
        ;;
    annotate)
        # slurp exits nonzero if the selection is cancelled — just abort quietly
        geom=$(slurp) || exit 0
        # Enter = copy + save + close; toolbar buttons also work (early-exit)
        grim -g "$geom" - | satty --filename - \
            --output-filename "$f" \
            --copy-command wl-copy \
            --actions-on-enter save-to-clipboard \
            --actions-on-enter save-to-file \
            --actions-on-enter exit \
            --early-exit
        [[ -f "$f" ]] && notify-send 'Screenshot' "Annotated: ${f##*/}"
        ;;
    *)
        echo "usage: $0 <full|annotate>" >&2
        exit 1
        ;;
esac
