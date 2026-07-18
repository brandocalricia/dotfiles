#!/usr/bin/env bash
# jot — capture a thought into the Obsidian brain from any terminal, instantly.
#   jot buy a new usb-c cable
#   jot "idea: cache the geolocation result for 10 min"
# Appends a timestamped bullet under today's date in Brain/Claude/Inbox.md.
# Claude surfaces unchecked Inbox items at session start (see brain-context hook).
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
inbox="$BRAIN/Inbox.md"
mkdir -p "$BRAIN" 2>/dev/null || { echo "jot: brain vault not found" >&2; exit 1; }

text="$*"
if [ -z "$text" ]; then
  # no args → read from stdin (allows: echo foo | jot)
  text="$(cat)"
fi
[ -z "${text// }" ] && { echo "usage: jot <text>"; exit 1; }

[ -f "$inbox" ] || printf -- '---\ntags: [claude/inbox]\n---\n# 📥 Inbox — quick captures\n\nUnchecked items are surfaced to Claude at session start. Check off (`- [x]`) when handled.\n\n' > "$inbox"

day=$(date +%Y-%m-%d); ts=$(date +%H:%M); host=$(hostname -s 2>/dev/null || hostname)
# Ensure a heading for today exists, then append the item.
grep -qxF "## $day" "$inbox" || printf '\n## %s\n' "$day" >> "$inbox"
printf -- '- [ ] %s · _%s_ · %s\n' "$text" "$host" "$ts" >> "$inbox"
echo "jotted → $inbox"
