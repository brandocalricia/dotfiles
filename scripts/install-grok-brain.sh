#!/usr/bin/env bash
# install-grok-brain.sh — wire the Obsidian "brain" into Grok Build.
# User scope (no sudo). Idempotent. Safe to re-run on any machine.
#
# Does NOT clobber the Claude setup. Run install-claude-brain.sh as well
# during the overlap month. This script only touches:
#   ~/.grok/config.toml   (a marked managed block; rest of the file is left alone)
#   ~/.grok/hooks/brain.json
#   chmod on the hook scripts in this repo
#
# It will not rewrite ~/.claude/settings.json, CLAUDE.md, or the vault path.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GROK_DIR="${GROK_HOME:-$HOME/.grok}"
BRAIN="$HOME/Documents/Brain/Claude"
mkdir -p "$GROK_DIR/hooks" "$GROK_DIR/rules" "$GROK_DIR/memory" \
         "$BRAIN/Sessions" "$BRAIN/Memory" "$BRAIN/Rollups"

startcmd="$DOTFILES/scripts/claude-brain-context.sh"
endcmd="$DOTFILES/scripts/claude-session-log.sh"
promptcmd="$DOTFILES/scripts/brain-retrieve.py"
stopcmd="$DOTFILES/scripts/brain-capture-check.py"
guardcmd="$DOTFILES/scripts/grok-cwd-guard.sh"
chmod +x "$startcmd" "$endcmd" "$promptcmd" "$stopcmd" "$guardcmd" 2>/dev/null || true

# 1. Native hooks file (always-trusted global). Identical command paths are
#    deduplicated against ~/.claude/settings.json if Claude-compat is on.
cat > "$GROK_DIR/hooks/brain.json" <<EOF
{
  "hooks": {
    "SessionStart": [{
      "hooks": [
        {"type": "command", "command": "$startcmd", "timeout": 15},
        {"type": "command", "command": "$guardcmd", "timeout": 5}
      ]
    }],
    "UserPromptSubmit": [{
      "hooks": [
        {"type": "command", "command": "$promptcmd", "timeout": 10}
      ]
    }],
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "$stopcmd", "timeout": 10}
      ]
    }],
    "SessionEnd": [{
      "hooks": [
        {"type": "command", "command": "$endcmd", "timeout": 20}
      ]
    }],
    "PreToolUse": [{
      "hooks": [
        {"type": "command", "command": "$guardcmd", "timeout": 5}
      ]
    }]
  }
}
EOF
echo "[+] $GROK_DIR/hooks/brain.json written"

# 2. Merge a marked block into ~/.grok/config.toml. Never rewrite the rest of
#    the file (Grok itself writes installer/marketplace/ui keys).
python3 - "$GROK_DIR/config.toml" "$HOME" <<'PY'
import sys
from pathlib import Path
cfg_path = Path(sys.argv[1])
home = sys.argv[2]
text = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
begin, end = "# >>> grok-brain managed", "# <<< grok-brain managed"
block = f"""{begin}
# Written by install-grok-brain.sh. Edit the script, not this block, then re-run.
[features]
telemetry = false
feedback = false

[telemetry]
trace_upload = false
mixpanel_enabled = false
otel_enabled = false
otel_log_user_prompts = false
otel_log_tool_details = false

[compat.claude]
skills = true
rules = true
agents = true
mcps = true
hooks = true
sessions = true

[memory]
enabled = true

[memory.session]
save_on_end = true

[memory.initial_injection]
enabled = true
min_score = 0.7

[permission]
deny = [
  "Read(**/.env)",
  "Read(**/.env.*)",
  "Read(**/secrets.env)",
  "Read(**/.git-credentials)",
  "Read(**/.credentials.json)",
  "Read(**/*.pem)",
  "Read(**/*.key)",
  "Read(~/.ssh/**)",
  "Read(~/.gnupg/**)",
  "Read(**/.ssh/**)",
  "Read(**/.gnupg/**)",
  "Read({home}/.ssh/**)",
  "Read({home}/.gnupg/**)",
  "Read({home}/.config/secrets.env)",
  "Read({home}/.git-credentials)",
  "Read({home}/.claude/.credentials.json)",
  "Edit(**/.env)",
  "Edit(**/.env.*)",
  "Edit(**/secrets.env)",
  "Edit(**/.git-credentials)",
  "Edit(**/.credentials.json)",
  "Edit(**/*.pem)",
  "Edit(**/*.key)",
  "Edit(~/.ssh/**)",
  "Edit(~/.gnupg/**)",
  "Edit(**/.ssh/**)",
  "Edit(**/.gnupg/**)",
  "Edit({home}/.ssh/**)",
  "Edit({home}/.gnupg/**)",
  "Edit({home}/.config/secrets.env)",
  "Edit({home}/.git-credentials)",
  "Edit({home}/.claude/.credentials.json)",
]
{end}
"""
if begin in text and end in text:
    pre = text.split(begin, 1)[0]
    post = text.split(end, 1)[1]
    # drop a leading leftover newline in post
    if post.startswith("\n"):
        post = post[1:]
    new = pre.rstrip() + "\n\n" + block
    if post.strip():
        new = new + "\n" + post.lstrip()
else:
    new = (text.rstrip() + "\n\n" if text.strip() else "") + block
cfg_path.parent.mkdir(parents=True, exist_ok=True)
cfg_path.write_text(new if new.endswith("\n") else new + "\n", encoding="utf-8")
print(f"[+] {cfg_path} managed block upserted")
PY

# 3. Seed the Grok rules side-channel so the *next* session has INDEX even
#    before the first SessionStart rewrite. Harmless if the vault isn't synced yet.
if [ -x "$startcmd" ]; then
  printf '%s' '{"source":"new","hookEventName":"session_start"}' \
    | GROK_HOOK_EVENT=session_start "$startcmd" >/dev/null 2>&1 \
    && echo "[+] ~/.grok/rules/brain-session-context.md seeded" \
    || echo "[=] SessionStart seed skipped (vault not present yet?)"
fi

echo "[+] Grok brain wired. Restart Grok / run \`grok inspect\` to confirm hooks."
echo "    Claude setup was not touched. Keep using install-claude-brain.sh too."
