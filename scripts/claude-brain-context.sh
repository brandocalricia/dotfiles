#!/usr/bin/env bash
# claude-brain-context.sh — Claude Code SessionStart hook.
# Injects the knowledge base into every session automatically: INDEX + recent
# session history + open Inbox captures. Bounded so it stays cheap.
set -uo pipefail

BRAIN="$HOME/Documents/Brain/Claude"
json=$(cat 2>/dev/null || true)
# Dump stdin so we can empirically compare Claude vs Grok payloads.
mkdir -p "$HOME/.cache/brain-hooks" 2>/dev/null || true
printf '%s' "$json" > "$HOME/.cache/brain-hooks/sessionstart.stdin.json" 2>/dev/null || true
printf '%s\n' "GROK_HOOK_EVENT=${GROK_HOOK_EVENT-}" "CLAUDE_PROJECT_DIR=${CLAUDE_PROJECT_DIR-}" "GROK_SESSION_ID=${GROK_SESSION_ID-}" > "$HOME/.cache/brain-hooks/sessionstart.env" 2>/dev/null || true
# Grok is camelCase; Claude is snake_case. Prefer source, then Grok's matcher field.
source=$(printf '%s' "$json" | jq -r '.source // .startSource // "startup"' 2>/dev/null || echo startup)

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
# Each item is stamped with the date heading it sits under and, once it's been
# sitting for more than a week, an explicit age. Without that a capture just
# rots quietly: it shows up identically on day 1 and day 90, so it reads as
# "new" forever and never gets handled.
inbox=""
if [ -f "$BRAIN/Inbox.md" ]; then
  inbox=$(awk -v today="$(date +%s)" '
    /^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ { day = $2; next }
    /^- \[ \]/ {
      age = -1
      if (day != "") {
        cmd = "date -d " day " +%s 2>/dev/null"
        cmd | getline t; close(cmd)
        if (t > 0) age = int((today - t) / 86400)
      }
      if (age > 7)  { printf "%s · **%dd old**\n", $0, age }
      else          { print $0 }
    }
  ' "$BRAIN/Inbox.md" 2>/dev/null | head -n 15)
  inbox_stale=$(printf '%s' "$inbox" | grep -c 'd old\*\*' || true)
  [ "${inbox_stale:-0}" -gt 0 ] && inbox=$(printf '%s\n(%s capture(s) older than a week — ask whether to handle or drop them.)' "$inbox" "$inbox_stale")
fi

# Off-device backup status (restic → B2). Same visibility as the health score:
# if a run failed or the last ok snapshot is older than 48h, it is in front of
# every session. Script is read-only, no secrets.
restic=""
if [ -x "$HOME/dotfiles/scripts/restic-status.sh" ]; then
  restic=$("$HOME/dotfiles/scripts/restic-status.sh" 2>/dev/null || true)
fi

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
  # Criterion 4: one line per audit day, so the two-week trend is a file not memory.
  mkdir -p "$HOME/.cache/brain-hooks" 2>/dev/null || true
  if [ -n "$hdate" ] && [ -n "$hscore" ]; then
    if ! awk -v d="$hdate" '$1==d {f=1} END{exit !f}' "$HOME/.cache/brain-hooks/health-trend.tsv" 2>/dev/null; then
      printf '%s\t%s\t%s\n' "$hdate" "$hscore" "${hnotes}" >> "$HOME/.cache/brain-hooks/health-trend.tsv" 2>/dev/null || true
    fi
  fi
  # Surface the top unwritten concepts so gaps are visible without being asked.
  if [ -f "$BRAIN/Health.md" ]; then
    queue=$(sed -n '/^## Write queue/,/^## /p' "$BRAIN/Health.md" | grep '^- \*\*' | head -n 5)
    [ -n "$queue" ] && health=$(printf '%s\nTop unwritten concepts (linked but never written):\n%s' "$health" "$queue")
  fi
fi

# Nothing to inject → stay silent (fresh machine before Syncthing).
[ -z "$index$recent$inbox$health$restic" ] && exit 0

ctx=$(printf '# Knowledge base (auto-loaded from ~/Documents/Brain/Claude)\n\nThe user'"'"'s persistent brain — treat as current context. Keep INDEX.md'"'"'s "Active threads" current as work changes; log meaningful decisions to today'"'"'s Sessions note.\n' )
if [ -n "$health$restic" ]; then
  vh="$health"
  [ -n "$restic" ] && vh=$(printf '%s\n%s' "${vh}" "$restic")
  ctx=$(printf '%s\n## Vault health\n%s\n' "$ctx" "$vh")
fi
ctx=$(printf '%s\n%s\n' "$ctx" "$index")
[ -n "$inbox" ] && ctx=$(printf '%s\n\n## Open captures (Inbox / jot) — surface these if relevant\n%s\n' "$ctx" "$inbox")
[ -n "$recent" ] && ctx=$(printf '%s\n\n---\n## Recent session history\n%s\n' "$ctx" "$recent")

# Retrieval-status banner. Grok 1.0.5 cannot inject UserPromptSubmit stdout
# (probed exhaustively 2026-08-23). Must be visible every session, not once.
generated=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
status_line="Retrieval: **CONFIRMED WORKING** on Claude Code (UserPromptSubmit additionalContext)."
if [ -n "${GROK_HOOK_EVENT-}" ] || [ "${source}" = "new" ]; then
  status_line="Retrieval: **DEGRADED** on Grok Build 1.0.5. UserPromptSubmit stdout/stderr/exit codes do not reach the model. Before answering questions about the user's projects, setup, decisions, tools, machines, games, or history, call \`brain_search\` with their prompt first. Not optional."
fi
if [ -f "$HOME/.cache/brain-hooks/retrieval-status.json" ] && command -v jq >/dev/null; then
  hts=$(jq -r '.ts // empty' "$HOME/.cache/brain-hooks/retrieval-status.json" 2>/dev/null || true)
  hmatch=$(jq -r '.matched // empty' "$HOME/.cache/brain-hooks/retrieval-status.json" 2>/dev/null || true)
  [ -n "$hts" ] && status_line=$(printf '%s Last hook heartbeat: %s (matched=%s).' "$status_line" "$hts" "$hmatch")
fi
banner=$(printf '## Retrieval status\n%s\n_generated %s, may be one session behind unless `grok` was launched via the zsh wrapper._\n' "$status_line" "$generated")
ctx=$(printf '%s\n%s\n' "$banner" "$ctx")

# Hard cap. Raised 6000→7500 when the restic status line was added so INDEX
# does not get clipped first on a normal session.
ctx=$(printf '%s' "$ctx" | head -c 7500)

# Grok 1.0.5 fires SessionStart but ignores stdout/additionalContext (verified
# 2026-08-23: hook ran in 22ms, INDEX never reached the API). Side-channel:
# write the same payload into ~/.grok/rules/ so the NEXT Grok session loads it
# as a home rule. Claude does not read that directory; overlap stays intact.
# Same-session re-read of rules files does NOT reach the model (probed).
if [ -n "${GROK_HOOK_EVENT-}" ] || [ "${source}" = "new" ]; then
  mkdir -p "$HOME/.grok/rules" 2>/dev/null || true
  {
    printf '%s\n' '<!-- auto-generated by claude-brain-context.sh; do not edit -->'
    printf '%s\n' "$ctx"
  } > "$HOME/.grok/rules/brain-session-context.md" 2>/dev/null || true
fi

if command -v jq >/dev/null 2>&1; then
  out=$(printf '%s' "$ctx" | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}')
else
  out=$ctx
fi
mkdir -p "$HOME/.cache/brain-hooks" 2>/dev/null || true
printf '%s' "$out" > "$HOME/.cache/brain-hooks/sessionstart.stdout.json" 2>/dev/null || true
printf '%s' "$out"
exit 0
