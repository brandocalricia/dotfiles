#!/usr/bin/env bash
# grok-cwd-guard.sh — refuse/warn when Grok is launched from a dangerous cwd.
# Wired as SessionStart (loud warning) and PreToolUse (hard deny in $HOME and ~/Brain).
#
# Dangerous:
#   $HOME              — whole-home git-ish launches; 0.2.93 tarball blast radius
#   ~/Brain            — old git-tracked clone (renamed 2026-08-23)
#   ~/Brain.linux-mint-archive-2026-05 — that clone's archive; still a git repo
#   any repo with .env — the tracked-files vs gitignored leak vector
set -uo pipefail

json=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$json" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -z "$cwd" ] && cwd="${PWD:-}"
event="${GROK_HOOK_EVENT:-}"

HOME_DIR="${HOME}"
BRAIN_GIT="${HOME}/Brain"
BRAIN_ARCHIVE="${HOME}/Brain.linux-mint-archive-2026-05"
# The Syncthing vault is ~/Documents/Brain. Launching *there* is fine.
# ~/Brain was a separate git-tracked clone; renamed 2026-08-23.

is_home=0
is_brain_git=0
has_env=0
env_path=""

# Resolve cwd (don't follow symlink out of the launch dir's identity).
abs=$(readlink -f "$cwd" 2>/dev/null || printf '%s' "$cwd")
home_abs=$(readlink -f "$HOME_DIR" 2>/dev/null || printf '%s' "$HOME_DIR")
brain_abs=$(readlink -f "$BRAIN_GIT" 2>/dev/null || printf '%s' "$BRAIN_GIT")
archive_abs=$(readlink -f "$BRAIN_ARCHIVE" 2>/dev/null || printf '%s' "$BRAIN_ARCHIVE")

[ "$abs" = "$home_abs" ] && is_home=1
case "$abs" in
  "$brain_abs"|"$brain_abs"/*) is_brain_git=1 ;;
  "$archive_abs"|"$archive_abs"/*) is_brain_git=1 ;;
esac

# Walk up for a .env sitting in a git repo (tracked or gitignored — both leaked
# under 0.2.93 if the agent read the file; tracked ones also hit the tarball).
dir="$abs"
while [ -n "$dir" ] && [ "$dir" != "/" ]; do
  if [ -f "$dir/.env" ]; then
    has_env=1
    env_path="$dir/.env"
    break
  fi
  [ -d "$dir/.git" ] || [ -f "$dir/.git" ] || true
  parent=$(dirname "$dir")
  [ "$parent" = "$dir" ] && break
  dir="$parent"
done

warn() {
  printf '%s\n' "$1" >&2
}

deny() {
  # PreToolUse: JSON deny. SessionStart stdout is ignored, so stderr is the
  # only same-session signal there.
  if [ "$event" = "pre_tool_use" ]; then
    printf '%s\n' "{\"decision\":\"deny\",\"reason\":$(printf '%s' "$1" | jq -Rs .)}"
    exit 2
  fi
  warn "$1"
  exit 0
}

if [ "$is_home" -eq 1 ]; then
  deny "GROK CWD GUARD: refused. You launched Grok from \$HOME. Grok Build 0.2.93 uploaded whole git repos + .env contents; \$HOME is the blast radius. cd into a project (not \$HOME, not ~/Brain) and relaunch."
fi

if [ "$is_brain_git" -eq 1 ]; then
  deny "GROK CWD GUARD: refused. That directory is the old git-tracked GitHub vault clone (or its 2026-08-23 archive). Work in ~/Documents/Brain (Syncthing live vault) or a project repo — never the GitHub clone."
fi

if [ "$has_env" -eq 1 ]; then
  env_dir=$(dirname "$env_path")
  tracked=0
  if git -C "$env_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    rel=$(realpath --relative-to="$(git -C "$env_dir" rev-parse --show-toplevel)" "$env_path" 2>/dev/null || true)
    if [ -n "$rel" ] && git -C "$env_dir" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
      tracked=1
    fi
  fi
  if [ "$tracked" -eq 1 ]; then
    deny "GROK CWD GUARD: refused. ${env_path} is TRACKED in git — that is the 0.2.93 tarball vector. Move the secrets out of the repo (or gitignore them) before launching Grok here."
  fi
  # gitignored .env: Read/Edit deny rules cover the tool layer. Warn every session
  # because a bash wrapper (python app.py that loads dotenv) still runs.
  warn "GROK CWD GUARD: WARNING — gitignored ${env_path} is present. Deny rules block Read/Edit of **/.env at the tool layer; do not assume a subprocess cannot load it. Prefer not launching Grok from a secrets repo."
fi

exit 0
