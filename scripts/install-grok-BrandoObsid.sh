#!/usr/bin/env bash
# install-grok-BrandoObsid.sh — Grok extras that are safe to re-run on any machine.
# User scope (no sudo). Idempotent.
#
# BrandoObsid (~/Documents/BrandoObsid) is a manual notebook. This installer must NOT
# inject, search, log, or write the vault. It only touches:
#   ~/.grok/config.toml   (a marked managed block; rest of the file is left alone)
#   ~/.grok/hooks/BrandoObsid.json          (cwd guard only)
#   ~/.grok/hooks/done-notify.json    (turn-finished banner)
#   ~/.grok/rules + ~/.grok/commands  (opt-in vault read)
#
# It will not rewrite ~/.claude/settings.json or the vault path.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GROK_DIR="${GROK_HOME:-$HOME/.grok}"
mkdir -p "$GROK_DIR/hooks" "$GROK_DIR/rules" "$GROK_DIR/memory"

guardcmd="$DOTFILES/scripts/grok-cwd-guard.sh"
mcpcmd="$DOTFILES/scripts/BrandoObsid-mcp-server.py"
telcmd="$DOTFILES/scripts/grok-telemetry-guard.sh"
notifycmd="$DOTFILES/scripts/grok-done-notify.sh"
chmod +x "$guardcmd" "$mcpcmd" "$telcmd" "$notifycmd" \
          "$DOTFILES/scripts/restic-status.sh" "$DOTFILES/scripts/BrandoObsid-status.sh" 2>/dev/null || true
mkdir -p "$HOME/.local/bin"
ln -sfn "$DOTFILES/scripts/restic-status.sh" "$HOME/.local/bin/restic-status"
ln -sfn "$DOTFILES/scripts/BrandoObsid-status.sh" "$HOME/.local/bin/BrandoObsid-status"
rm -f "$HOME/.local/bin/brain-status" "$HOME/.local/bin/obsidian-status"
# Native copies so Grok still works if ~/.claude is gone.
mkdir -p "$GROK_DIR/commands"
if [ -d "$DOTFILES/claude/commands" ]; then
  rm -f "$GROK_DIR/commands/"{brain,brain-note,brain-audit,brain-fix,obsidian,obsidian-note,obsidian-audit,obsidian-fix}.md
  cp -f "$DOTFILES/claude/commands/"*.md "$GROK_DIR/commands/" 2>/dev/null || true
fi
if [ -f "$DOTFILES/claude/CLAUDE.md" ]; then
  cp -f "$DOTFILES/claude/CLAUDE.md" "$GROK_DIR/rules/00-global-context.md"
fi

if [ "${1-}" = "--dry-run" ]; then
  cat <<PLAN
install-grok-BrandoObsid.sh --dry-run (no writes)
host=$(hostname -s 2>/dev/null || hostname)
GROK_DIR=$GROK_DIR
DOTFILES=$DOTFILES

Would chmod +x:
  $guardcmd
  $mcpcmd
  $telcmd
  $notifycmd

Would write $GROK_DIR/hooks/BrandoObsid.json
  SessionStart: grok-cwd-guard.sh
  PreToolUse: grok-cwd-guard.sh
  (no vault inject / retrieve / session-log / capture)

Would write $GROK_DIR/hooks/done-notify.json
  Notification task_complete + Stop: grok-done-notify.sh

Would upsert marked block in $GROK_DIR/config.toml
  [features] telemetry=false feedback=false
  [telemetry] trace_upload=false (and mixpanel/otel off)
  [compat.claude] skills/rules/agents/mcps/hooks/sessions = true
  [memory] enabled=true  [memory.session] save_on_end=true
  [mcp_servers.BrandoObsid] $mcpcmd
  [permission] deny Read/Edit on .env, secrets.env, credentials, ssh, gnupg
  (preserves any existing allow = [...] so a re-run does not wipe Bash allows)

Would mkdir -p:
  $GROK_DIR/{hooks,rules,memory}

Would copy $GROK_DIR/rules/{00-global-context,this-machine,BrandoObsid-search-obligation,BrandoObsid-name}.md
Would write a short $GROK_DIR/rules/BrandoObsid-session-context.md (no vault dump)
Would NOT create or write ~/Documents/BrandoObsid/**

Would install user systemd units (if present in repo):
  grok-telemetry-guard.path + .service → enable --now
  then run $telcmd

Would NOT touch:
  ~/.claude/  settings.json  settings.local.json
  ~/Documents/BrandoObsid (no reads, no writes, no mkdir)
  display manager, sudo, NetworkManager

zsh grok() wrapper: lives in ~/dotfiles/zsh/.zshrc (stowed). This script
does not rewrite .zshrc. Laptop gets it on the next dotfiles pull + stow.
PLAN
  if grep -q 'grok() {' "$HOME/.zshrc" 2>/dev/null; then
    echo "zsh grok() wrapper: PRESENT in ~/.zshrc"
  else
    echo "zsh grok() wrapper: MISSING from ~/.zshrc — pull+stow ~/dotfiles (zsh/.zshrc)"
  fi
  echo "Claude hooks: $( [ -f "$HOME/.claude/settings.json" ] && echo PRESENT, left alone || echo none )"
  exit 0
fi

# 1. Native hooks file (always-trusted global). No vault inject/log/capture.
cat > "$GROK_DIR/hooks/BrandoObsid.json" <<EOF
{
  "hooks": {
    "SessionStart": [{
      "hooks": [
        {"type": "command", "command": "$guardcmd", "timeout": 5}
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
echo "[+] $GROK_DIR/hooks/BrandoObsid.json written (cwd-guard only)"
# Claude-compat also loads this file; it used to re-inject INDEX + session logs.
cat > "$GROK_DIR/hooks/imported-from-claude.json" <<EOF
{
  "hooks": {}
}
EOF
echo "[+] $GROK_DIR/hooks/imported-from-claude.json cleared"

# Top-right banner when a turn finishes (macOS Notification Center / notify-send).
cat > "$GROK_DIR/hooks/done-notify.json" <<EOF
{
  "hooks": {
    "Notification": [{
      "matcher": "task_complete",
      "hooks": [
        {"type": "command", "command": "$notifycmd", "timeout": 5}
      ]
    }],
    "Stop": [{
      "hooks": [
        {"type": "command", "command": "$notifycmd", "timeout": 5}
      ]
    }]
  }
}
EOF
echo "[+] $GROK_DIR/hooks/done-notify.json written"

# 2. Merge a marked block into ~/.grok/config.toml. Never rewrite the rest of
#    the file (Grok itself writes installer/marketplace/ui keys).
python3 - "$GROK_DIR/config.toml" "$HOME" <<'PY'
import sys
from pathlib import Path
cfg_path = Path(sys.argv[1])
home = sys.argv[2]
text = cfg_path.read_text(encoding="utf-8") if cfg_path.exists() else ""
# Drop the pre-rename managed block so we do not leave mcp_servers.brain behind.
for old_begin, old_end in (
    ("# >>> grok-brain managed", "# <<< grok-brain managed"),
):
    if old_begin in text and old_end in text:
        pre = text.split(old_begin, 1)[0]
        post = text.split(old_end, 1)[1]
        text = pre.rstrip() + "\n" + post.lstrip()
begin, end = "# >>> grok-BrandoObsid managed", "# <<< grok-BrandoObsid managed"
# Keep any native allow = [...] when rewriting the managed [permission]
# table. Re-running this installer used to wipe the 136 Bash allows ported
# from Claude. deny list below is still the source of truth for denials.
import re
allow_m = re.search(r"(?ms)^allow\s*=\s*\[.*?\]\s*\n", text)
allow_block = allow_m.group(0) if allow_m else ""
block = f"""{begin}
# Written by install-grok-BrandoObsid.sh. Edit the script, not this block, then re-run.
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

[mcp_servers.BrandoObsid]
command = "{home}/dotfiles/scripts/BrandoObsid-mcp-server.py"
enabled = true
startup_timeout_sec = 15

[permission]
{allow_block}deny = [
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

# 3. Static rules. No vault dump, no INDEX, no "must search before every answer".
cp -f "$DOTFILES/claude/this-machine.md" "$GROK_DIR/rules/this-machine.md"
cp -f "$DOTFILES/claude/BrandoObsid-name.md" "$GROK_DIR/rules/BrandoObsid-name.md"
cp -f "$DOTFILES/claude/BrandoObsid-search-obligation.md" "$GROK_DIR/rules/BrandoObsid-search-obligation.md"
rm -f "$GROK_DIR/rules/obsidian-name.md" \
      "$GROK_DIR/rules/brain-search-obligation.md" \
      "$GROK_DIR/rules/brain-session-context.md" \
      "$GROK_DIR/hooks/brain.json"
cat > "$GROK_DIR/rules/BrandoObsid-session-context.md" <<'EOF'
<!-- static; do not auto-generate from the vault -->
BrandoObsid (`~/Documents/BrandoObsid`) is a manual notebook. Do not search or write it unless the user asks.
Identify this host with `hostname -s`.
EOF

# Old auto-write timers must not come back (new names and leftover brain-* names).
systemctl --user disable --now BrandoObsid-rollup.timer 2>/dev/null || true
systemctl --user disable --now BrandoObsid-doctor.timer 2>/dev/null || true
systemctl --user disable --now brain-rollup.timer 2>/dev/null || true
systemctl --user disable --now brain-doctor.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/brain-rollup.service" \
      "$HOME/.config/systemd/user/brain-rollup.timer" \
      "$HOME/.config/systemd/user/brain-doctor.service" \
      "$HOME/.config/systemd/user/brain-doctor.timer"
systemctl --user daemon-reload 2>/dev/null || true

# Telemetry path unit — re-checks kill switches when the binary is replaced.
if [ -f "$DOTFILES/systemd/grok-telemetry-guard.path" ]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$DOTFILES/systemd/grok-telemetry-guard.path" "$DOTFILES/systemd/grok-telemetry-guard.service" \
    "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now grok-telemetry-guard.path 2>/dev/null \
    && echo "[+] grok-telemetry-guard.path enabled" || true
  "$telcmd" && echo "[+] telemetry guard OK" || echo "[!] telemetry guard FAIL (see above)"
fi

if grep -q 'grok() {' "$HOME/.zshrc" 2>/dev/null; then
  echo "[+] zsh grok() wrapper present in ~/.zshrc (stowed from dotfiles/zsh/.zshrc)"
else
  echo "[!] zsh grok() wrapper MISSING from ~/.zshrc"
  echo "    Pull ~/dotfiles and restow zsh."
fi

echo "[+] Grok extras wired (cwd-guard, notify, on-demand vault MCP). Restart Grok to pick up hooks."
echo "    BrandoObsid is manual. Claude settings were not touched — run install-claude-BrandoObsid.sh to strip its vault hooks too."
