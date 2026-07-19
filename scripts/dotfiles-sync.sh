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

# Bootstrap/self-heal in-session helpers that arrive via a pull. A brand-new
# exec-once (e.g. captive-portal-watch.sh) can't start itself on the first boot
# after it lands, because at login the file isn't pulled yet and Hyprland's
# exec-once has already fired. This sync runs shortly after login (and every
# 15 min), so once it has pulled the file it starts the helper into the live
# Hyprland session — no second reboot, no manual step. Idempotent (skips if
# already running), and it also revives a helper that has died. Launched via
# `hyprctl dispatch exec` so the child inherits Hyprland's Wayland/DBus env even
# though this sync runs as a background user service.
ensure_session_helpers() {
  local rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  # Only act if a Hyprland session is actually running — find its instance
  # signature from the socket dir ($XDG_RUNTIME_DIR/hypr/<sig>/). Use a glob, not
  # `ls`, so nothing (aliases, locale) can perturb the parse. If no instance dir
  # matches, the literal glob fails the -d test and we bail.
  local sig="" d
  for d in "$rt"/hypr/*/; do [ -d "$d" ] && { sig="${d%/}"; sig="${sig##*/}"; }; done
  [ -n "$sig" ] || return 0
  command -v hyprctl >/dev/null 2>&1 || return 0

  local watcher="$HOME/.config/hypr/captive-portal-watch.sh"
  if [ -x "$watcher" ] && ! pgrep -f '[c]aptive-portal-watch\.sh' >/dev/null 2>&1; then
    HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl dispatch exec "$watcher" >/dev/null 2>&1 \
      && log "started captive-portal watcher into the running Hyprland session"
  fi
}

# Always pull first so we build on the other machine's latest.
git pull --rebase --autostash --quiet || { log "rebase hit a conflict — resolve manually in $REPO"; exit 2; }

# CRITICAL: `pull --rebase --autostash` exits 0 even when re-applying the autostash
# CONFLICTS, leaving unmerged paths. A blind `git add -A` would then commit conflict
# markers (this actually happened once). Never commit a conflicted tree — bail loudly.
if [ -n "$(git ls-files --unmerged)" ]; then
  log "unmerged paths after pull (autostash conflict) — NOT committing; fix by hand in $REPO"
  exit 2
fi

# Now that the pull has landed, make sure session helpers are up (see above).
ensure_session_helpers

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
