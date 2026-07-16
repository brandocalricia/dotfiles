#!/usr/bin/env bash
# work-status.sh — cross-machine work awareness over the Syncthing-shared ~/code.
# Each host periodically writes its OWN heartbeat file (never the other's, so there
# are no sync conflicts) to ~/code/.sync-status/<host>.status; Syncthing carries the
# files both ways for free. Reading them shows what every machine was last doing.
#
#   work-status.sh            print every host's latest heartbeat (default)
#   work-status.sh update     write THIS host's heartbeat (run by work-heartbeat.timer)
#
# Heartbeat = current project (top-level dir under ~/code with the newest file),
# its git branch, the last-touched file, and timestamps. Driven by
# work-heartbeat.timer every 5 min; run by hand any time.
set -uo pipefail

CODE="${CODE_DIR:-$HOME/code}"
STATUS_DIR="$CODE/.sync-status"

host="$(hostnamectl --static 2>/dev/null || true)"
host="${host:-$(hostname)}"   # --static can print empty; fall back to hostname

# ── update: write this host's heartbeat ───────────────────────────
do_update() {
  mkdir -p "$STATUS_DIR"

  # Newest regular file under ~/code, ignoring VCS + syncthing internals.
  # Output of stat: "<epoch> <path>"; keep the single newest.
  newest="$(fd -t f -H -E .git -E .sync-status -E '.stfolder*' -E '.stversions' \
              . "$CODE" -x stat -c '%Y %n' 2>/dev/null | sort -rn | head -1)"

  project="-" branch="-" last_file="-" file_mtime=""
  if [ -n "$newest" ]; then
    file_mtime="${newest%% *}"
    path="${newest#* }"
    rel="${path#"$CODE"/}"
    project="${rel%%/*}"
    last_file="$rel"
    proj_dir="$CODE/$project"
    if git -C "$proj_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      branch="$(git -C "$proj_dir" branch --show-current 2>/dev/null)"
      branch="${branch:-detached}"
    fi
  fi

  # Write atomically so Syncthing never ships a half-written file.
  tmp="$STATUS_DIR/.$host.status.tmp"
  {
    echo "host=$host"
    echo "updated=$(date +%s)"
    echo "updated_iso=$(date +%Y-%m-%dT%H:%M:%S%z)"
    echo "project=$project"
    echo "branch=$branch"
    echo "last_file=$last_file"
    echo "file_mtime=$file_mtime"
  } > "$tmp"
  mv "$tmp" "$STATUS_DIR/$host.status"
}

# ── show: print every host's heartbeat ────────────────────────────
age() {  # epoch -> "3m ago" / "2h ago" / "5d ago"
  local s=$(( $(date +%s) - $1 ))
  if   [ "$s" -lt 60 ];    then echo "${s}s ago"
  elif [ "$s" -lt 3600 ];  then echo "$(( s / 60 ))m ago"
  elif [ "$s" -lt 86400 ]; then echo "$(( s / 3600 ))h ago"
  else                          echo "$(( s / 86400 ))d ago"
  fi
}

do_show() {
  shopt -s nullglob
  local files=("$STATUS_DIR"/*.status)
  if [ ${#files[@]} -eq 0 ]; then
    echo "work-status: no heartbeats in $STATUS_DIR yet (run 'work-status update')"
    return 1
  fi
  for f in "${files[@]}"; do
    # shellcheck disable=SC2034  # keys are read via the sourced vars below
    local h="" updated="" project="" branch="" last_file="" file_mtime=""
    while IFS='=' read -r k v; do
      case "$k" in
        host) h="$v" ;; updated) updated="$v" ;; project) project="$v" ;;
        branch) branch="$v" ;; last_file) last_file="$v" ;; file_mtime) file_mtime="$v" ;;
      esac
    done < "$f"
    local mark="●" me=""
    [ "$h" = "$host" ] && me="  (this machine)"
    echo "$mark $h$me — heartbeat $(age "${updated:-0}")"
    if [ "$project" = "-" ]; then
      echo "    no projects in ~/code yet"
    else
      echo "    project:   $project  (branch: $branch)"
      echo "    last file: $last_file  ($(age "${file_mtime:-0}"))"
    fi
  done
}

case "${1:-show}" in
  update) do_update ;;
  show)   do_show ;;
  *) echo "usage: work-status [show|update]" >&2; exit 64 ;;
esac
