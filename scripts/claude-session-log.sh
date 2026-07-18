#!/usr/bin/env bash
# claude-session-log.sh — Claude Code SessionEnd hook.
# Writes a RICH, deterministic record of every session to the Obsidian brain by
# mining the transcript — goal, files touched, activity — with zero reliance on
# the model choosing to summarize. Also refreshes the memory mirror.
# Receives hook JSON on stdin: { session_id, transcript_path, cwd, reason, ... }
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
SESS="$BRAIN/Sessions"
mkdir -p "$SESS" "$BRAIN/Memory" 2>/dev/null || exit 0

json=$(cat 2>/dev/null || true)
get(){ printf '%s' "$json" | jq -r "$1 // empty" 2>/dev/null; }
tp=$(get '.transcript_path'); cwd=$(get '.cwd'); reason=$(get '.reason')
[ -z "$cwd" ] && cwd="$PWD"

# ── Mine the transcript (all deterministic) ──────────────────────────────────
goal="(session)"; files=""; nfiles=0; ncmds=0; ncommits=0; nprompts=0
if [ -n "$tp" ] && [ -f "$tp" ]; then
  read -r -d '' extract <<'JQ' || true
  ( [ .[] | select(.type=="user") | .message.content
      | if type=="array" then (map(select(.type=="text").text)|join(" ")) else . end ]
    | map(select(. != null and (test("^\\s*$")|not) and (startswith("<")|not) and (startswith("Caveat")|not))) ) as $prompts
  | [ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") ] as $t
  | ($t | map(select(.name|test("^(Edit|Write|MultiEdit|NotebookEdit)$")) | .input.file_path) | map(select(.!=null)) | unique) as $files
  | ($t | map(select(.name=="Bash") | .input.command // empty)) as $cmds
  | { goal: ($prompts[0] // "(session)"),
      prompts: ($prompts|length),
      files: ($files | map(sub("^/home/[^/]+/";"~/"))),
      nfiles: ($files|length),
      ncmds: ($cmds|length),
      ncommits: ($cmds | map(select(test("git commit"))) | length) }
JQ
  data=$(jq -rs "$extract" "$tp" 2>/dev/null)
  if [ -n "$data" ]; then
    goal=$(printf '%s' "$data" | jq -r '.goal' 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g' | cut -c1-200)
    nfiles=$(printf '%s' "$data" | jq -r '.nfiles' 2>/dev/null)
    ncmds=$(printf '%s' "$data" | jq -r '.ncmds' 2>/dev/null)
    ncommits=$(printf '%s' "$data" | jq -r '.ncommits' 2>/dev/null)
    nprompts=$(printf '%s' "$data" | jq -r '.prompts' 2>/dev/null)
    files=$(printf '%s' "$data" | jq -r '.files[]?' 2>/dev/null | sed 's/^/    - `/; s/$/`/')
  fi
fi
[ -z "$goal" ] && goal="(session)"

# ── Context: machine + repo ──────────────────────────────────────────────────
gitinfo=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root=$(basename "$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)")
  br=$(git -C "$cwd" branch --show-current 2>/dev/null)
  gitinfo=" · \`$root\`@${br:-?}"
fi
day=$(date +%Y-%m-%d); ts=$(date +%H:%M); host=$(hostname -s 2>/dev/null || hostname)
file="$SESS/$day.md"
[ -f "$file" ] || printf -- '---\ntags: [claude/session]\ndate: %s\n---\n# Sessions — %s\n\n' "$day" "$day" > "$file"

# ── Append a structured entry ────────────────────────────────────────────────
{
  printf -- '## %s · %s%s\n' "$ts" "$host" "$gitinfo"
  printf -- '- **Goal:** %s\n' "$goal"
  printf -- '- **Activity:** %s prompts · %s files · %s commands · %s commits\n' \
    "${nprompts:-0}" "${nfiles:-0}" "${ncmds:-0}" "${ncommits:-0}"
  if [ -n "$files" ]; then printf -- '- **Files touched:**\n%s\n' "$files"; fi
  [ -n "$reason" ] && printf -- '- _ended: %s_\n' "$reason"
  [ -n "$tp" ] && printf -- '- transcript: `%s`\n' "$tp"
  printf '\n'
} >> "$file"

# ── Refresh the memory mirror (real copies → synced + graphed) ───────────────
for md in "$HOME"/.claude/projects/*/memory; do
  [ -d "$md" ] && cp -f "$md"/*.md "$BRAIN/Memory/" 2>/dev/null || true
done
exit 0
