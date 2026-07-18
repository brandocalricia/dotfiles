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
mkdir -p "$CLAUDE_DIR" "$BRAIN/Sessions" "$BRAIN/Memory" "$BRAIN/Rollups"

# 0. Seed starter brain notes if missing (so the SessionStart hook works even
#    before Syncthing pairs). The real INDEX/Dashboard sync in and win.
for f in INDEX.md Dashboard.md README.md; do
  [ -f "$BRAIN/$f" ] || { cp "$DOTFILES/claude/brain-seed/$f" "$BRAIN/$f" 2>/dev/null && echo "[+] seeded $f"; }
done

# 1. Global pointer — don't clobber a customized one that already references the brain.
if [ ! -f "$CLAUDE_DIR/CLAUDE.md" ] || ! grep -q 'Documents/Brain' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null; then
  cp "$DOTFILES/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "[+] global CLAUDE.md installed"
else
  echo "[=] global CLAUDE.md already points at the brain"
fi

# 2. Hooks — SessionStart (inject brain) + SessionEnd (log session). Idempotent.
settings="$CLAUDE_DIR/settings.json"
[ -f "$settings" ] || echo '{}' > "$settings"
startcmd="$DOTFILES/scripts/claude-brain-context.sh"
endcmd="$DOTFILES/scripts/claude-session-log.sh"
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg s "$startcmd" --arg e "$endcmd" '
    .hooks = (.hooks // {}) |
    .hooks.SessionStart = ((.hooks.SessionStart // [])
      | if any(.[]?.hooks[]?; .command == $s) then .
        else . + [{"hooks":[{"type":"command","command":$s,"timeout":15}]}] end) |
    .hooks.SessionEnd = ((.hooks.SessionEnd // [])
      | if any(.[]?.hooks[]?; .command == $e) then .
        else . + [{"hooks":[{"type":"command","command":$e,"timeout":20}]}] end)
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" \
    && echo "[+] SessionStart + SessionEnd hooks ensured" || echo "[!] jq merge failed"
else
  echo "[!] jq missing — add the hooks manually"
fi

# 3. Seed the memory mirror.
for md in "$HOME"/.claude/projects/*/memory; do
  [ -d "$md" ] && cp -f "$md"/*.md "$BRAIN/Memory/" 2>/dev/null || true
done
echo "[+] Claude brain wired. Restart Claude Code / open /hooks once for the hook to load."
