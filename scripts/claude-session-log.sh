#!/usr/bin/env bash
# claude-session-log.sh — Claude Code SessionEnd hook.
# Writes a RICH, deterministic record of every session to the Obsidian brain by
# mining the transcript — goal, files touched, activity — with zero reliance on
# the model choosing to summarize. Also refreshes the memory mirror.
# Receives hook JSON on stdin: { session_id, transcript_path, cwd, reason, ... }
set -uo pipefail

# Recall-bench sessions are throwaway grok -p runs. Do not append them to the
# real working-day SessionEnd note.
if [ "${BRAIN_RECALL_BENCH-}" = "1" ]; then
  exit 0
fi

BRAIN="$HOME/Documents/Brain/Claude"
SESS="$BRAIN/Sessions"
mkdir -p "$SESS" "$BRAIN/Memory" 2>/dev/null || exit 0

json=$(cat 2>/dev/null || true)
mkdir -p "$HOME/.cache/brain-hooks" 2>/dev/null || true
printf '%s' "$json" > "$HOME/.cache/brain-hooks/sessionend.stdin.json" 2>/dev/null || true
printf '%s\n' "GROK_HOOK_EVENT=${GROK_HOOK_EVENT-}" "GROK_SESSION_ID=${GROK_SESSION_ID-}" > "$HOME/.cache/brain-hooks/sessionend.env" 2>/dev/null || true
get(){ printf '%s' "$json" | jq -r "$1 // empty" 2>/dev/null; }
# Claude: transcript_path. Grok: transcriptPath (camelCase).
tp=$(get '.transcript_path // .transcriptPath')
cwd=$(get '.cwd'); reason=$(get '.reason')
[ -z "$cwd" ] && cwd="$PWD"

# ── Mine the transcript (Claude JSONL and Grok chat_history.jsonl) ──────────
goal="(session)"; files=""; nfiles=0; ncmds=0; ncommits=0; nprompts=0
# Grok Stop/SessionEnd point at updates.jsonl; the conversation is the sibling.
if [ -n "$tp" ] && [ -f "$tp" ]; then
  case "$tp" in
    */updates.jsonl)
      sibling="${tp%/*}/chat_history.jsonl"
      [ -f "$sibling" ] && tp="$sibling"
      ;;
  esac
fi
if [ -n "$tp" ] && [ -f "$tp" ]; then
  data=$(python3 - "$tp" <<'PY' 2>/dev/null
import json, sys, re
from pathlib import Path
path = Path(sys.argv[1])
prompts, files, cmds = [], [], []
WRITE = {"Write", "Edit", "MultiEdit", "NotebookEdit", "write", "search_replace"}
BASH = {"Bash", "run_terminal_command"}
def load_args(raw):
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            v = json.loads(raw)
            return v if isinstance(v, dict) else {}
        except ValueError:
            return {}
    return {}
def homeish(p):
    return re.sub(r"^/home/[^/]+/", "~/", p)
def unwrap_user(text):
    """Grok TUI wraps prompts in <user_query>; skip other harness XML."""
    if not text or text.isspace():
        return ""
    text = text.strip()
    m = re.search(r"<user_query>\s*(.*?)\s*</user_query>", text, re.S)
    if m:
        return m.group(1).strip()
    if text.startswith("<") or text.startswith("Caveat"):
        return ""
    return text
try:
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
except OSError:
    print("{}"); raise SystemExit
for line in lines:
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    msg = ev.get("message") or {}
    if msg:
        role = msg.get("role") or ev.get("type")
        content = msg.get("content")
        if role == "user":
            text = ""
            if isinstance(content, str):
                text = content
            elif isinstance(content, list):
                text = " ".join(b.get("text") or "" for b in content if isinstance(b, dict) and b.get("type") == "text")
            text = unwrap_user(text)
            if text:
                prompts.append(text)
        elif role == "assistant" and isinstance(content, list):
            for b in content:
                if not isinstance(b, dict) or b.get("type") != "tool_use":
                    continue
                name = b.get("name") or ""
                inp = b.get("input") or {}
                if name in WRITE and inp.get("file_path"):
                    files.append(inp["file_path"])
                if name in BASH and inp.get("command"):
                    cmds.append(inp["command"])
        continue
    t = ev.get("type")
    if t == "user":
        if ev.get("synthetic_reason"):
            continue
        content = ev.get("content")
        texts = []
        if isinstance(content, str):
            texts.append(content)
        elif isinstance(content, list):
            for b in content:
                if isinstance(b, dict):
                    texts.append(b.get("text") or "")
                elif isinstance(b, str):
                    texts.append(b)
        text = unwrap_user(" ".join(texts))
        if not text:
            continue
        if "prompt_index" in ev or not text.startswith("Caveat"):
            prompts.append(text)
    elif t == "assistant":
        for tc in ev.get("tool_calls") or []:
            if not isinstance(tc, dict):
                continue
            name = tc.get("name") or ""
            inp = load_args(tc.get("arguments"))
            if name in WRITE and (inp.get("file_path") or inp.get("path")):
                files.append(inp.get("file_path") or inp.get("path"))
            if name in BASH and inp.get("command"):
                cmds.append(inp["command"])
uniq, seen = [], set()
for f in files:
    if f not in seen:
        seen.add(f); uniq.append(homeish(f))
print(json.dumps({
    "goal": (prompts[0] if prompts else "(session)"),
    "prompts": len(prompts),
    "files": uniq,
    "nfiles": len(uniq),
    "ncmds": len(cmds),
    "ncommits": sum(1 for c in cmds if "git commit" in c),
}))
PY
)
  if [ -n "$data" ] && [ "$data" != "{}" ]; then
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
# Redact secrets before anything reaches the vault. The goal line is the user's
# FIRST prompt verbatim, and a session that opens by pasting an API key would
# otherwise write that key into Brain/Claude/Sessions/ — which Syncthing copies
# to the laptop and restic ships to B2. Cheap insurance on a one-way mistake.
redact() {
  printf '%s' "$1" | sed -E \
    -e 's/\b(sk|pk|rk|ak)-[A-Za-z0-9_-]{16,}/[REDACTED-KEY]/g' \
    -e 's/\bghp_[A-Za-z0-9]{20,}/[REDACTED-GITHUB-TOKEN]/g' \
    -e 's/\bgh[pousr]_[A-Za-z0-9]{20,}/[REDACTED-GITHUB-TOKEN]/g' \
    -e 's/\bxox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED-SLACK-TOKEN]/g' \
    -e 's/\bAKIA[0-9A-Z]{16}\b/[REDACTED-AWS-KEY]/g' \
    -e 's/(eyJ[A-Za-z0-9_-]{10,})\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED-JWT]/g' \
    -e 's/\b[A-Za-z0-9_-]*(API|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE)[A-Za-z0-9_-]*[[:space:]]*[=:][[:space:]]*[^[:space:]]{8,}/[REDACTED-SECRET]/gI'
}
goal=$(redact "$goal")

file="$SESS/$day.md"
[ -f "$file" ] || printf -- '---\ntags: [claude/session]\ndate: %s\n---\n# Sessions — %s\n\n' "$day" "$day" > "$file"

# ── Append a structured entry ────────────────────────────────────────────────
{
  harness=""
  [ -n "${GROK_HOOK_EVENT-}" ] && harness=" · grok"
  printf -- '## %s · %s%s%s\n' "$ts" "$host" "$gitinfo" "$harness"
  printf -- '- **Goal:** %s\n' "$goal"
  printf -- '- **Activity:** %s prompts · %s files · %s commands · %s commits\n' \
    "${nprompts:-0}" "${nfiles:-0}" "${ncmds:-0}" "${ncommits:-0}"
  if [ -n "$files" ]; then printf -- '- **Files touched:**\n%s\n' "$files"; fi
  [ -n "$reason" ] && printf -- '- _ended: %s_\n' "$reason"
  [ -n "$tp" ] && printf -- '- transcript: `%s`\n' "$tp"
  printf '\n'
} >> "$file"

# ── Refresh the memory mirror (real copies → synced + graphed) ───────────────
# Claude per-project auto-memory (overlap month). Flattened on purpose — see
# install-claude-brain.sh for why we do not try to round-trip this.
for md in "$HOME"/.claude/projects/*/memory; do
  [ -d "$md" ] && cp -f "$md"/*.md "$BRAIN/Memory/" 2>/dev/null || true
done
# Grok one-fact files written at ~/.grok/memory/*.md (not the MEMORY.md index,
# not imported-from-claude/ which would clobber the Claude-shaped copies, not
# per-session sqlite dirs). Overlap-month: Claude flatten stays the source of
# the existing 20; new Grok facts land here too so Syncthing sees them.
find "$HOME/.grok/memory" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' \
  -exec cp -f {} "$BRAIN/Memory/" \; 2>/dev/null || true

# Criterion 2: count real Grok TUI working days (multi-turn, not grok -p probes).
# SessionEnd on a TUI session has GROK_HOOK_EVENT and a real prompt count.
# grok -p recall-bench is already bailed out above via BRAIN_RECALL_BENCH=1.
if [ -n "${GROK_HOOK_EVENT-}" ]; then
  mkdir -p "$HOME/.cache/brain-hooks" 2>/dev/null || true
  # multi-turn: 2+ user prompts, or any file/cmd work. Skip empty probes.
  if [ "${nprompts:-0}" -ge 2 ] || [ "${nfiles:-0}" -ge 1 ]; then
    printf '%s\t%s\t%s\t%s\n' "$day" "${nprompts:-0}" "${nfiles:-0}" "${ncmds:-0}" \
      >> "$HOME/.cache/brain-hooks/tui-days.tsv" 2>/dev/null || true
  fi
fi
exit 0
