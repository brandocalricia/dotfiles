#!/usr/bin/env bash
# Copy stdin with wl-copy, then return.
# grim | wl-copy deadlocks Hyprland: wl-copy waits on the compositor while
# the compositor is still inside the clipboard transaction, and every open
# window stops painting. Reading to a file first lets grim finish. timeout
# --foreground kills only a wl-copy parent that never finishes the handshake;
# a parent that already forked has exited, so the clipboard daemon stays up.
set -eu
mime="${1:-}"
tmp=$(mktemp /tmp/wlcopy.XXXXXX)
trap 'rm -f "$tmp"' EXIT
cat > "$tmp"
if [ ! -s "$tmp" ]; then
  exit 0
fi
if [ -z "$mime" ]; then
  magic=$(od -An -t x1 -N 8 "$tmp" | tr -d ' \n')
  if [ "$magic" = "89504e470d0a1a0a" ]; then
    mime="image/png"
  fi
fi
if [ -n "$mime" ]; then
  timeout --foreground 5 wl-copy --type "$mime" < "$tmp"
else
  timeout --foreground 5 wl-copy < "$tmp"
fi
