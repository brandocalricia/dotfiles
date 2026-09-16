#!/usr/bin/env bash
# install-claude-BrandoObsid.sh — keep Claude from auto-writing BrandoObsid.
# User scope (no sudo). Idempotent. Safe to re-run on any machine.
#
# BrandoObsid (~/Documents/BrandoObsid) is a manual notebook. This installer:
#   • installs the simple ~/.claude/CLAUDE.md policy
#   • removes SessionStart/SessionEnd/Stop/UserPromptSubmit vault hooks
#   • disables BrandoObsid-rollup / BrandoObsid-doctor timers (and old brain-* names)
#   • copies opt-in /BrandoObsid* slash commands
# It does not create vault folders or copy memory into the vault.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# 1. Global policy — always the simple one from this repo.
if [ -f "$DOTFILES/claude/CLAUDE.md" ]; then
  cp "$DOTFILES/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "[+] ~/.claude/CLAUDE.md (manual BrandoObsid policy)"
fi

# 2. Strip vault hooks. settings.json is a real file per machine, not stowed.
settings="$CLAUDE_DIR/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq '
    .hooks = (.hooks // {}) |
    .hooks.SessionStart = ((.hooks.SessionStart // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("claude-BrandoObsid-context|claude-brain-context|BrandoObsid-retrieve|brain-retrieve|BrandoObsid-capture|brain-capture|BrandoObsid-recall|brain-recall|claude-session-log") | not))))
      | map(select((.hooks | length) > 0))) |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("BrandoObsid-retrieve|brain-retrieve|claude-BrandoObsid-context|claude-brain-context|BrandoObsid-capture|brain-capture|BrandoObsid-recall|brain-recall|claude-session-log") | not))))
      | map(select((.hooks | length) > 0))) |
    .hooks.SessionEnd = ((.hooks.SessionEnd // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("claude-session-log|BrandoObsid-retrieve|brain-retrieve|BrandoObsid-capture|brain-capture|BrandoObsid-recall|brain-recall|claude-BrandoObsid-context|claude-brain-context") | not))))
      | map(select((.hooks | length) > 0))) |
    .hooks.Stop = ((.hooks.Stop // [])
      | map(.hooks = ((.hooks // []) | map(select((.command // "") | test("BrandoObsid-capture|brain-capture|BrandoObsid-recall|brain-recall|claude-session-log|BrandoObsid-retrieve|brain-retrieve|claude-BrandoObsid-context|claude-brain-context") | not))))
      | map(select((.hooks | length) > 0)))
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" \
    && echo "[+] vault hooks removed from ~/.claude/settings.json" \
    || echo "[!] jq merge failed"
else
  echo "[!] jq missing — remove vault hooks from ~/.claude/settings.json by hand"
fi

# 3. Kill auto-write timers (new names and leftover brain-* names).
for unit in BrandoObsid-rollup.timer BrandoObsid-doctor.timer brain-rollup.timer brain-doctor.timer; do
  systemctl --user disable --now "$unit" 2>/dev/null \
    && echo "[+] $unit disabled" || true
done

# 4. Opt-in slash commands (/BrandoObsid, /BrandoObsid-note, …).
if [ -d "$DOTFILES/claude/commands" ]; then
  mkdir -p "$CLAUDE_DIR/commands"
  rm -f "$CLAUDE_DIR/commands/"{brain,brain-note,brain-audit,brain-fix,obsidian,obsidian-note,obsidian-audit,obsidian-fix}.md
  cp -f "$DOTFILES/claude/commands"/*.md "$CLAUDE_DIR/commands/" 2>/dev/null \
    && echo "[+] vault slash commands installed (opt-in only)"
fi

echo "[+] Claude will not auto-write BrandoObsid. Restart Claude Code if it is running."
