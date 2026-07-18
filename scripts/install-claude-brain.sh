#!/usr/bin/env bash
# install-claude-brain.sh — wire the Obsidian "brain" into Claude Code.
# User scope (no sudo). Idempotent. Safe to re-run on any machine.
#   • installs the global ~/.claude/CLAUDE.md pointer
#   • merges the SessionEnd auto-log hook into ~/.claude/settings.json (via jq)
#   • creates the Brain/Claude structure + seeds the memory mirror
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
BRAIN="$HOME/Documents/Brain/Claude"
mkdir -p "$CLAUDE_DIR" "$BRAIN/Sessions" "$BRAIN/Memory"

# 1. Global pointer — don't clobber a customized one that already references the brain.
if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ] || ! grep -q 'Documents/Brain' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
  cp "$DOTFILES/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "[+] global CLAUDE.md installed"
else
  echo "[=] global CLAUDE.md already points at the brain"
fi

# 2. SessionEnd hook — merged idempotently (won't duplicate).
settings="$CLAUDE_DIR/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
hookcmd="$DOTFILES/scripts/claude-session-log.sh"
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg cmd "$hookcmd" '
    .hooks = (.hooks // {}) |
    .hooks.SessionEnd = ((.hooks.SessionEnd // [])
      | if any(.[]?.hooks[]?; .command == $cmd) then .
        else . + [{"hooks":[{"type":"command","command":$cmd,"timeout":20}]}] end)
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" \
    && echo "[+] SessionEnd auto-log hook ensured" || echo "[!] jq merge failed"
else
  echo "[!] jq missing — add the SessionEnd hook manually"
fi

# 3. Seed the memory mirror.
for md in "$HOME"/.claude/projects/*/memory; do
  [ -d "$md" ] && cp -f "$md"/*.md "$BRAIN/Memory/" 2>/dev/null || true
done
echo "[+] Claude brain wired. Restart Claude Code / open /hooks once for the hook to load."
