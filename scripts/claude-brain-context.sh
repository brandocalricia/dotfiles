#!/usr/bin/env bash
# claude-brain-context.sh — Claude Code SessionStart hook.
# Injects the knowledge base into every session automatically: INDEX + recent
# session history + open Inbox captures. Bounded so it stays cheap.
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
json=$(cat 2>/dev/null || true)
source=$(printf '%s' "$json" | jq -r '.source // "startup"' 2>/dev/null || echo startup)

# INDEX (capped to ~70 lines so a runaway file can't bloat every session).
index=""
[ -f "$BRAIN/INDEX.md" ] && index=$(head -n 70 "$BRAIN/INDEX.md")

# Most recent session history (last ~30 lines across the 2 newest day files).
recent=""
if [ -d "$BRAIN/Sessions" ]; then
  recent=$(ls -t "$BRAIN/Sessions"/*.md 2>/dev/null | head -2 | xargs -r tail -q -n 18 2>/dev/null | tail -n 30)
fi

# Open Inbox captures (from `jot`) — unchecked items only, capped.
inbox=""
[ -f "$BRAIN/Inbox.md" ] && inbox=$(grep '^- \[ \]' "$BRAIN/Inbox.md" 2>/dev/null | head -n 15)

# Nothing to inject → stay silent (fresh machine before Syncthing).
[ -z "$index$recent$inbox" ] && exit 0

ctx=$(printf '# Knowledge base (auto-loaded from ~/Documents/Brain/Claude)\n\nThe user'"'"'s persistent brain — treat as current context. Keep INDEX.md'"'"'s "Active threads" current as work changes; log meaningful decisions to today'"'"'s Sessions note.\n\n%s\n' "$index")
[ -n "$inbox" ] && ctx=$(printf '%s\n\n## Open captures (Inbox / jot) — surface these if relevant\n%s\n' "$ctx" "$inbox")
[ -n "$recent" ] && ctx=$(printf '%s\n\n---\n## Recent session history\n%s\n' "$ctx" "$recent")

# Hard cap total size (~6000 chars) as a final guard.
ctx=$(printf '%s' "$ctx" | head -c 6000)

if command -v jq >/dev/null 2>&1; then
  printf '%s' "$ctx" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
else
  printf '%s' "$ctx"
fi
exit 0
