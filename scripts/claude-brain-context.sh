#!/usr/bin/env bash
# claude-brain-context.sh — Claude Code SessionStart hook.
# Injects the knowledge base into EVERY session automatically (INDEX + the most
# recent session history), so Claude always starts with your context without
# having to decide to go read it. Output is bounded to stay cheap.
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
idx="$BRAIN/INDEX.md"

index=""
[ -f "$idx" ] && index=$(cat "$idx")

# Last ~30 lines across the two most recent session-day files.
recent=""
if [ -d "$BRAIN/Sessions" ]; then
  recent=$(ls -t "$BRAIN/Sessions"/*.md 2>/dev/null | head -2 | xargs -r tail -q -n 20 2>/dev/null | tail -n 40)
fi

ctx=$(printf '# Knowledge base (auto-loaded from ~/Documents/Brain/Claude)\n\nThis is the user'"'"'s persistent brain. Treat it as current context. Keep INDEX.md'"'"'s "Active threads" up to date as work changes.\n\n%s\n\n---\n## Recent session history\n%s\n' "$index" "$recent")

# Emit as SessionStart additionalContext (bounded).
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$ctx" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}'
else
  printf '%s' "$ctx"
fi
exit 0
