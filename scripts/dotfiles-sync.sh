#!/usr/bin/env bash
# dotfiles-sync.sh — auto-commit + push dotfiles config changes to the shared repo,
# and pull the other machine's changes. Because ~/.config/{hypr,waybar,...} are
# folded stow symlinks INTO this repo, any edit to live config IS a repo change,
# so a plain commit here captures everything. Gitignored per-host/generated files
# (bare local.*, style.css, colors.conf, secrets) are never committed — see
# .gitignore. Safe on 2 machines via pull --rebase --autostash.
#
# Driven by the dotfiles-sync.timer (every ~15 min) + shortly after login. Run by
# hand any time with: systemctl --user start dotfiles-sync.service
# (or directly: ~/dotfiles/scripts/dotfiles-sync.sh).
set -uo pipefail

REPO="${DOTFILES:-$HOME/dotfiles}"
cd "$REPO" 2>/dev/null || { echo "dotfiles-sync: no repo at $REPO" >&2; exit 1; }

log() { echo "[dotfiles-sync $(date +%H:%M:%S)] $*"; }

# Network preflight: don't thrash if offline (mirrors restic-backup-home's pattern).
if ! git ls-remote --exit-code origin >/dev/null 2>&1; then
  log "remote unreachable (offline?) — skipping this run"
  exit 0
fi

host="$(hostnamectl --static 2>/dev/null || true)"
host="${host:-$(hostname)}"   # --static can print empty; fall back to hostname

# Always pull first so we build on the other machine's latest.
git pull --rebase --autostash --quiet || { log "rebase hit a conflict — resolve manually in $REPO"; exit 2; }

# CRITICAL: `pull --rebase --autostash` exits 0 even when re-applying the autostash
# CONFLICTS, leaving unmerged paths. A blind `git add -A` would then commit conflict
# markers (this actually happened once). Never commit a conflicted tree — bail loudly.
if [ -n "$(git ls-files --unmerged)" ]; then
  log "unmerged paths after pull (autostash conflict) — NOT committing; fix by hand in $REPO"
  exit 2
fi

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
