#!/usr/bin/env bash
# wl-paste --watch feeds one clipboard image on stdin. Read it and return
# so Hyprland can finish the transfer. The cliphist db is large; doing the
# sqlite write in the watch command stalls every client waiting on that copy.
set -eu
tmp=$(mktemp /tmp/cliphist-img.XXXXXX)
cat > "$tmp" || { rm -f "$tmp"; exit 0; }
sz=$(stat -c%s "$tmp" 2>/dev/null || echo 0)
# Live clipboard is already held by wl-copy. History skips empty and huge frames.
if [ "$sz" -eq 0 ] || [ "$sz" -gt 20971520 ]; then
  rm -f "$tmp"
  exit 0
fi
(
  timeout --foreground 8 cliphist store < "$tmp"
  rm -f "$tmp"
) >/dev/null 2>&1 &
exit 0
