#!/usr/bin/env bash
# dotfiles-sync.sh — auto-commit + push dotfiles config changes to the shared repo,
# and pull the other machine's changes. Because ~/.config/{hypr,waybar,...} are
# folded stow symlinks INTO this repo, any edit to live config IS a repo change,
# so a plain commit here captures everything. Gitignored per-host/generated files
# (bare local.*, style.css, colors.conf, secrets) are never committed — see
# .gitignore. Safe on 2 machines via pull --rebase --autostash.
#
# Driven by the dotfiles-sync.timer (every ~15 min) + once on login. Also runnable
# by hand: `dotfiles-sync` (see the alias install.sh / zshrc sets up).
set -uo pipefail

REPO="${DOTFILES:-$HOME/dotfiles}"
cd "$REPO" 2>/dev/null || { echo "dotfiles-sync: no repo at $REPO" >&2; exit 1; }

log() { echo "[dotfiles-sync $(date +%H:%M:%S)] $*"; }

# Network preflight: don't thrash if offline (mirrors restic-backup-home's pattern).
if ! git ls-remote --exit-code origin >/dev/null 2>&1; then
  log "remote unreachable (offline?) — skipping this run"
  exit 0
fi

host="$(hostnamectl --static 2>/dev/null || hostname)"

# Always pull first so we build on the other machine's latest.
git pull --rebase --autostash --quiet || { log "rebase hit a conflict — resolve manually in $REPO"; exit 2; }

# Anything to commit?
if [ -z "$(git status --porcelain)" ]; then
  git push --quiet 2>/dev/null || true   # push any local commits made offline
  exit 0
fi

git add -A
git commit -q -m "auto(${host}): config snapshot $(date +%Y-%m-%dT%H:%M:%S%z)"
log "committed config changes on ${host}"

git push --quiet || { log "push failed — will retry next run"; exit 3; }
log "pushed to origin"
