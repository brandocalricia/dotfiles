#!/usr/bin/env bash
# One-line restic /home→B2 status. No sudo, no secrets.
# Exit 0 = healthy (snapshot ≤48h). Exit 1 = failed / stale / never / in progress.
set -uo pipefail

STATUS_USER="${HOME}/.cache/brain-hooks/restic-status.json"
STATUS_SYS=/var/lib/restic-backup-home/status.json
MAX_AGE=$((48 * 3600))

state=""; finished=""; snapshot=""; rc=""
load_status() {
  local f=$1
  [[ -r "$f" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    state=$(jq -r '.state // empty' "$f" 2>/dev/null || true)
    finished=$(jq -r '.finished // empty' "$f" 2>/dev/null || true)
    snapshot=$(jq -r '.snapshot // empty' "$f" 2>/dev/null || true)
    rc=$(jq -r '.rc // empty' "$f" 2>/dev/null || true)
  else
    # crude fallback
    state=$(sed -n 's/.*"state":"\([^"]*\)".*/\1/p' "$f" | head -1)
    finished=$(sed -n 's/.*"finished":"\([^"]*\)".*/\1/p' "$f" | head -1)
    snapshot=$(sed -n 's/.*"snapshot":"\([^"]*\)".*/\1/p' "$f" | head -1)
  fi
  [[ -n "$state" ]]
}

host=$(hostname -s 2>/dev/null || hostname)
timer_state=$(systemctl is-enabled restic-backup-home.timer 2>/dev/null || echo unknown)
in_progress=0
if pgrep -f 'restic backup /home' >/dev/null 2>&1; then
  in_progress=1
fi

load_status "$STATUS_USER" || load_status "$STATUS_SYS" || true

age_s=""
if [[ -n "${finished:-}" ]]; then
  ts=$(date -d "$finished" +%s 2>/dev/null || true)
  if [[ -n "${ts:-}" ]]; then
    age_s=$(( $(date +%s) - ts ))
  fi
fi
age_h=""
if [[ -n "${age_s:-}" && "$age_s" -ge 0 ]]; then
  age_h=$((age_s / 3600))
fi

snap_bit=""
[[ -n "${snapshot:-}" ]] && snap_bit=" \`${snapshot}\`"

if [[ "$in_progress" -eq 1 ]]; then
  printf 'Restic /home→B2 (host %s): **IN PROGRESS** (first/current snapshot still running). Timer: %s.\n' "$host" "$timer_state"
  exit 1
fi

if [[ "$timer_state" != "enabled" ]]; then
  extra=""
  [[ -n "$state" ]] && extra=" last state=${state}${snap_bit}"
  printf 'Restic /home→B2 (host %s): **TIMER DISABLED** — scheduled backups will not run.%s\n' "$host" "$extra"
  exit 1
fi

if [[ -z "$state" ]]; then
  printf 'Restic /home→B2 (host %s): **NEVER completed** a snapshot on this machine. Timer: %s.\n' "$host" "$timer_state"
  exit 1
fi

if [[ "$state" != "ok" ]]; then
  printf 'Restic /home→B2 (host %s): **FAILED** (state=%s rc=%s at %s). Timer: %s.\n' \
    "$host" "$state" "${rc:-?}" "${finished:-unknown}" "$timer_state"
  exit 1
fi

if [[ -n "${age_s:-}" && "$age_s" -gt "$MAX_AGE" ]]; then
  printf 'Restic /home→B2 (host %s): **STALE** last ok snapshot%s %sh ago (threshold 48h) at %s.\n' \
    "$host" "$snap_bit" "${age_h:-?}" "$finished"
  exit 1
fi

printf 'Restic /home→B2 (host %s): last snapshot%s %sh ago (%s). Timer: %s.\n' \
  "$host" "$snap_bit" "${age_h:-0}" "$finished" "$timer_state"
exit 0
