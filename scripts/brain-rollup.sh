#!/usr/bin/env bash
# brain-rollup.sh — weekly self-curation of the brain (deterministic, no LLM).
# Aggregates the last 7 days of Claude session notes into one digest so the brain
# summarizes itself over time. Driven by brain-rollup.timer (weekly). Idempotent.
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
SESS="$BRAIN/Sessions"
ROLL="$BRAIN/Rollups"
mkdir -p "$ROLL" 2>/dev/null || exit 0
[ -d "$SESS" ] || exit 0

week=$(date +%G-W%V)                       # ISO year-week, e.g. 2026-W29
out="$ROLL/$week.md"
since=$(date -d '7 days ago' +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)

# Collect this week's session files (by filename date >= since).
files=$(find "$SESS" -maxdepth 1 -name '*.md' 2>/dev/null | sort | awk -v s="$since" -F/ '{d=$NF; sub(/\.md$/,"",d); if (d>=s) print}')
[ -z "$files" ] && { echo "brain-rollup: no sessions this week"; exit 0; }

goals=$(grep -h '^- \*\*Goal:\*\*' $files 2>/dev/null | sed 's/^- \*\*Goal:\*\*/  -/' | sort -u)
sessions_n=$(grep -h '^## ' $files 2>/dev/null | grep -c '·' || echo 0)
days_n=$(printf '%s\n' "$files" | grep -c . || echo 0)
open_inbox=$(grep -h '^- \[ \]' "$BRAIN/Inbox.md" 2>/dev/null | sed 's/^- \[ \]/  - [ ]/' || true)

{
  printf -- '---\ntags: [claude/rollup]\nweek: %s\n---\n# 🗓️ Weekly rollup — %s\n\n' "$week" "$week"
  printf -- '_Auto-generated %s. Covers %s → today._\n\n' "$(date +%Y-%m-%d)" "$since"
  printf -- '**Activity:** %s sessions across %s day(s).\n\n' "${sessions_n:-0}" "${days_n:-0}"
  printf -- '## What I worked on\n%s\n\n' "${goals:-  - (no goals recorded)}"
  if [ -n "$open_inbox" ]; then printf -- '## Still open (Inbox)\n%s\n\n' "$open_inbox"; fi
  printf -- '## Session notes this week\n'
  for f in $files; do printf -- '- [[Sessions/%s]]\n' "$(basename "$f" .md)"; done
} > "$out"

echo "brain-rollup: wrote $out"
