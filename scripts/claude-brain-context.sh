#!/usr/bin/env bash
# claude-brain-context.sh — Claude Code SessionStart hook.
# Injects the knowledge base into every session automatically: INDEX + recent
# session history + open Inbox captures. Bounded so it stays cheap.
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
json=$(cat 2>/dev/null || true)
source=$(printf '%s' "$json" | jq -r '.source // "startup"' 2>/dev/null || echo startup)

# peek asks short questions about the screen, not about the vault, and pays a
# cache WRITE for this whole preamble on every new session. Measured: the full
# preamble is ~11KB and a fresh peek session cost $0.062 just to boot. So peek
# gets the active-thread headlines and the health line only — enough to know
# what's going on, without the session history and full INDEX body.
peek_mode="${PEEK:-0}"

index=""
if [ -f "$BRAIN/INDEX.md" ]; then
  if [ "$peek_mode" = "1" ]; then
    # Bold headline of each active thread. Scoped to the "## Active threads"
    # section — a bare grep also matches the "- **Config:**" style labels in the
    # setup sections above it, which are noise here.
    index=$(sed -n '/^## Active threads/,/^## /p' "$BRAIN/INDEX.md" 2>/dev/null \
            | grep -oE '^- \*\*[^*]+\*\*' | head -n 8)
    [ -n "$index" ] && index="Active threads (titles only; ask if you need detail):
$index"
  else
    # INDEX capped to ~70 lines so a runaway file can't bloat every session.
    index=$(head -n 70 "$BRAIN/INDEX.md")
  fi
fi

# Most recent session history (last ~30 lines across the 2 newest day files).
# Skipped entirely for peek — it is the largest block and the least relevant to
# "what is on my screen".
recent=""
if [ "$peek_mode" != "1" ] && [ -d "$BRAIN/Sessions" ]; then
  recent=$(ls -t "$BRAIN/Sessions"/*.md 2>/dev/null | head -2 | xargs -r tail -q -n 18 2>/dev/null | tail -n 30)
fi

# Open Inbox captures (from `jot`) — unchecked items only, capped.
inbox=""
[ -f "$BRAIN/Inbox.md" ] && inbox=$(grep '^- \[ \]' "$BRAIN/Inbox.md" 2>/dev/null | head -n 15)

# Vault health (written by brain-doctor.py; timer keeps it fresh).
health=""
if [ -f "$BRAIN/.health-score" ]; then
  read -r hscore hnotes hdate < "$BRAIN/.health-score"
  stale=""
  if [ -n "${hdate:-}" ]; then
    age=$(( ( $(date +%s) - $(date -d "$hdate" +%s 2>/dev/null || date +%s) ) / 86400 ))
    [ "$age" -gt 10 ] && stale=" (audit ${age}d stale — run \`brain-doctor.py --all\`)"
  fi
  health="Vault health: **${hscore}/100** · ${hnotes} notes · checked ${hdate}${stale}. Detail: \`Claude/Health.md\`."
  # Surface the top unwritten concepts so gaps are visible without being asked.
  if [ -f "$BRAIN/Health.md" ]; then
    queue=$(sed -n '/^## Write queue/,/^## /p' "$BRAIN/Health.md" | grep '^- \*\*' | head -n 5)
    [ -n "$queue" ] && health=$(printf '%s\nTop unwritten concepts (linked but never written):\n%s' "$health" "$queue")
  fi
fi

# Nothing to inject → stay silent (fresh machine before Syncthing).
[ -z "$index$recent$inbox$health" ] && exit 0

ctx=$(printf '# Knowledge base (auto-loaded from ~/Documents/Brain/Claude)\n\nThe user'"'"'s persistent brain — treat as current context. Keep INDEX.md'"'"'s "Active threads" current as work changes; log meaningful decisions to today'"'"'s Sessions note.\n' )
[ -n "$health" ] && ctx=$(printf '%s\n## Vault health\n%s\n' "$ctx" "$health")
ctx=$(printf '%s\n%s\n' "$ctx" "$index")
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
