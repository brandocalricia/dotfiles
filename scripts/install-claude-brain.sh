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
promptcmd="$DOTFILES/scripts/brain-retrieve.py"
# Stop hook: blocks the end of a substantive session once if nothing was written
# to the vault, so capture stops depending on Claude remembering to do it. Stays
# silent on short/mechanical sessions, when a note was already written, and under
# PEEK=1 (peek is a one-question window, not a work session).
# NOTE: ~/.claude is NOT stowed — settings.json is a real file on each machine,
# not a symlink into the repo. That is exactly why this lives in the installer:
# it is the only thing that carries the hooks across machines.
stopcmd="$DOTFILES/scripts/brain-capture-check.py"
if command -v jq >/dev/null 2>&1; then
  tmp=$(mktemp)
  jq --arg s "$startcmd" --arg e "$endcmd" --arg p "$promptcmd" --arg k "$stopcmd" '
    .hooks = (.hooks // {}) |
    .hooks.SessionStart = ((.hooks.SessionStart // [])
      | if any(.[]?.hooks[]?; .command == $s) then .
        else . + [{"hooks":[{"type":"command","command":$s,"timeout":15}]}] end) |
    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // [])
      | if any(.[]?.hooks[]?; .command == $p) then .
        else . + [{"hooks":[{"type":"command","command":$p,"timeout":10}]}] end) |
    .hooks.SessionEnd = ((.hooks.SessionEnd // [])
      | if any(.[]?.hooks[]?; .command == $e) then .
        else . + [{"hooks":[{"type":"command","command":$e,"timeout":20}]}] end) |
    .hooks.Stop = ((.hooks.Stop // [])
      | if any(.[]?.hooks[]?; .command == $k) then .
        else . + [{"hooks":[{"type":"command","command":$k,"timeout":10}]}] end)
  ' "$settings" > "$tmp" && mv "$tmp" "$settings" \
    && echo "[+] SessionStart + UserPromptSubmit + SessionEnd + Stop hooks ensured" || echo "[!] jq merge failed"
else
  echo "[!] jq missing — add the hooks manually"
fi
chmod +x "$stopcmd" 2>/dev/null || true

# 3. Push the memory mirror into the vault (local -> vault, overwriting; the
#    SessionEnd hook does the same and the vault copy is a mirror, not a source).
#
# Deliberately one-way. Pulling the mirror back onto a second machine looks like
# the obvious way to carry auto-memory across machines — it is not, and this is
# the note explaining why so it doesn't get "fixed" later:
#
#   This loop flattens EVERY project's memory dir into one folder. On this
#   machine that is ~/.claude/projects/-home-brandonrobertniehaus/memory (15
#   files) and .../-home-brandonrobertniehaus-dotfiles/memory (2 files), merged.
#   Once merged, which project a file came from is unrecoverable, so copying the
#   pile back would drop dotfiles-project memories into the home project and vice
#   versa. Tried it; it seeded 26 files into the wrong project and was reverted.
#
# Consequence, worth knowing: auto-memory does NOT cross machines. It is not
# stowed and not Syncthing'd, so the laptop keeps its own. The vault mirror is a
# human-readable reference, not a restore point. Making it a real restore point
# means mirroring per-project (Claude/Memory/<project>/...) in this script AND in
# claude-session-log.sh — a vault-layout change, not a one-liner.
for md in "$HOME"/.claude/projects/*/memory; do
  [ -d "$md" ] && cp -f "$md"/*.md "$BRAIN/Memory/" 2>/dev/null || true
done

# 4. Weekly self-curation rollup (user timer, no sudo).
if [ -f "$DOTFILES/systemd/brain-rollup.timer" ]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$DOTFILES/systemd/brain-rollup.service" "$DOTFILES/systemd/brain-rollup.timer" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now brain-rollup.timer 2>/dev/null && echo "[+] brain-rollup.timer enabled (weekly)" || true
fi

# 5. Weekly vault health audit + safe auto-repair (brain-doctor).
if [ -f "$DOTFILES/systemd/brain-doctor.timer" ]; then
  mkdir -p "$HOME/.config/systemd/user"
  cp "$DOTFILES/systemd/brain-doctor.service" "$DOTFILES/systemd/brain-doctor.timer" "$HOME/.config/systemd/user/"
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now brain-doctor.timer 2>/dev/null && echo "[+] brain-doctor.timer enabled (weekly)" || true
fi

# 6. Vault slash commands (/brain, /brain-audit, /brain-fix, /brain-note).
if [ -d "$DOTFILES/claude/commands" ]; then
  mkdir -p "$CLAUDE_DIR/commands"
  cp -f "$DOTFILES/claude/commands"/*.md "$CLAUDE_DIR/commands/" 2>/dev/null \
    && echo "[+] vault slash commands installed"
fi

echo "[+] Claude brain wired. Restart Claude Code / open /hooks once for the hook to load."
