#!/usr/bin/env bash
# claude-session-log.sh — Claude Code SessionEnd hook.
# Appends a one-line record of every session to the Obsidian brain and mirrors
# Claude's memory files into the vault (real copies, so Syncthing propagates them
# and Obsidian graphs them). This is the deterministic safety-net capture; Claude
# also writes richer notes per the global ~/.claude/CLAUDE.md directive.
#
# Receives hook JSON on stdin: { session_id, transcript_path, cwd, reason, ... }
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
SESS="$BRAIN/Sessions"
mkdir -p "$SESS" "$BRAIN/Memory" 2>/dev/null || exit 0

json=$(cat 2>/dev/null || true)
get(){ printf '%s' "$json" | jq -r "$1 // empty" 2>/dev/null; }
tp=$(get '.transcript_path'); cwd=$(get '.cwd'); reason=$(get '.reason')
[ -z "$cwd" ] && cwd="$PWD"

# Topic = first real user prompt (content may be a string or block array).
topic=""
if [ -n "$tp" ] && [ -f "$tp" ]; then
  topic=$(jq -r 'select(.type=="user") | .message.content
                 | if type=="array" then (map(select(.type=="text").text)|join(" ")) else . end' \
             "$tp" 2>/dev/null | grep -vE '^\s*$|^<|^\[' | head -1 | tr -d '\n' | cut -c1-120)
fi
[ -z "$topic" ] && topic="(session)"

# Git context, if the session ran inside a repo.
gitinfo=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
  br=$(git -C "$cwd" branch --show-current 2>/dev/null)
  gitinfo=" · \`$root\`@${br:-?}"
fi

day=$(date +%Y-%m-%d); ts=$(date +%H:%M); host=$(hostname -s 2>/dev/null || hostname)
file="$SESS/$day.md"
[ -f "$file" ] || printf -- '---\ntags: [claude/session]\n---\n# Sessions — %s\n\n' "$day" > "$file"
{
  printf -- '- **%s** [%s]%s — %s' "$ts" "$host" "$gitinfo" "$topic"
  [ -n "$reason" ] && printf ' _(%s)_' "$reason"
  [ -n "$tp" ] && printf '\n  - transcript: `%s`' "$tp"
  printf '\n'
} >> "$file"

# Mirror Claude memory into the vault (copies, not symlinks → sync/graph safe).
for md in "$HOME"/.claude/projects/*/memory; do
  [ -d "$md" ] && cp -f "$md"/*.md "$BRAIN/Memory/" 2>/dev/null || true
done

exit 0
