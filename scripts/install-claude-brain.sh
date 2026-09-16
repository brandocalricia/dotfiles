#!/usr/bin/env bash
# install-claude-brain.sh — keep Claude from auto-writing Obsidian.
# User scope (no sudo). Idempotent. Safe to re-run on any machine.
#
# Obsidian (~/Documents/Brain) is a manual notebook. This installer:
#   • installs the simple ~/.claude/CLAUDE.md policy
#   • removes SessionStart/SessionEnd/Stop/UserPromptSubmit vault hooks
#   • disables brain-rollup / brain-doctor timers
#   • copies opt-in /obsidian* slash commands
# It does not create vault folders or copy memory into the vault.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# 1. Global policy — always the simple one from this repo.
if [ -f "$DOTFILES/claude/CLAUDE.md" ]; then
  cp "$DOTFILES/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "[+] ~/.claude/CLAUDE.md (manual Obsidian policy)"
fi

# 2. Strip vault hooks. settings.json is a real file per machine, not stowed.
settings="$CLAUDE_DIR/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '
    .hooks = (.hooks // {}) |
    .hooks.SessionStart = ((.hooks.SessionStart // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("claude-brain-context|brain-retrieve|brain-capture|brain-recall|claude-session-log") | not))))
      | map(select((.hooks | length) > 0))) |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("brain-retrieve|claude-brain-context|brain-capture|brain-recall|claude-session-log") | not))))
      | map(select((.hooks | length) > 0))) |
    .hooks.SessionEnd = ((.hooks.SessionEnd // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("claude-session-log|brain-retrieve|brain-capture|brain-recall|claude-brain-context") | not))))
      | map(select((.hooks | length) > 0))) |
    .hooks.Stop = ((.hooks.Stop // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("brain-capture|brain-recall|claude-session-log|brain-retrieve|claude-brain-context") | not))))
      | map(select((.hooks | length) > 0)))
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" \
    && echo "[+] vault hooks removed from ~/.claude/settings.json" \
    || echo "[!] jq merge failed"
else
  echo "[!] jq missing — remove vault hooks from ~/.claude/settings.json by hand"
fi

# 3. Kill auto-Obsidian timers.
systemctl --user disable --now brain-rollup.timer 2>/dev/null \
  && echo "[+] brain-rollup.timer disabled" || true
systemctl --user disable --now brain-doctor.timer 2>/dev/null \
  && echo "[+] brain-doctor.timer disabled" || true

# 4. Opt-in slash commands (/obsidian, /obsidian-note, …).
if [ -d "$DOTFILES/claude/commands" ]; then
  mkdir -p "$CLAUDE_DIR/commands"
  cp -f "$DOTFILES/claude/commands"/*.md "$CLAUDE_DIR/commands/" 2>/dev/null \
    && echo "[+] vault slash commands installed (opt-in only)"
fi

echo "[+] Claude will not auto-write Obsidian. Restart Claude Code if it is running."
