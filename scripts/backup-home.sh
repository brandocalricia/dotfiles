#!/usr/bin/env bash
# Off-device encrypted backup of /home to Backblaze B2 via restic.
# Secrets are NOT in this file or in git: they live in /etc/restic/b2-home.env
# (B2 keys + repo URL, 0600 root) and /etc/restic/home-repo.pass (passphrase,
# 0600 root). See SETUP-NOTES.md. Runs as root (systemd service or manual sudo).
set -euo pipefail

ENV_FILE=/etc/restic/b2-home.env
# NOTE: this script is INSTALLED to /usr/local/sbin/restic-backup-home.sh and the
# exclude file to /etc/restic/. They must NOT run from /home: under enforcing
# SELinux, systemd's service domain (init_t) cannot exec/read user_home_t files
# (fails 203/EXEC). The dotfiles copies are the source of truth; install.sh /
# the setup step copies them into these system paths + runs restorecon.
EXCLUDES=/etc/restic/restic-home-excludes.txt
LOG=/var/log/restic-backup-home.log
LOCKFILE=/run/restic-backup-home.lock

log() { printf '%s  %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }

# --- load secrets (systemd also injects these via EnvironmentFile; harmless) ---
if [[ ! -r "$ENV_FILE" ]]; then
  log "FATAL: $ENV_FILE missing or unreadable (are you root?)"; exit 1
fi
set -a; # shellcheck disable=SC1090
source "$ENV_FILE"; set +a

if [[ ! -r "$EXCLUDES" ]]; then
  log "FATAL: exclude file $EXCLUDES not found"; exit 1
fi

# --- restic local cache ---
# Under systemd there is no $HOME, so restic would run cacheless (re-fetching
# the repo index from B2 every op = slow + extra transactions). Point it at a
# persistent system cache instead.
export RESTIC_CACHE_DIR="${RESTIC_CACHE_DIR:-/var/cache/restic}"
install -d -m 700 "$RESTIC_CACHE_DIR"

# --- single instance: skip cleanly if a run is already in progress ---
exec 9>"$LOCKFILE"
if ! flock -n 9; then
  log "another backup run is in progress; exiting"; exit 0
fi

# --- clear stale repo lock from a previously interrupted run ---
# 'restic unlock' only removes locks whose owning process is dead. The flock
# above guarantees no other copy of THIS script is running, so any lingering
# lock here is stale (e.g. the laptop slept mid-backup). Safe and automatic.
restic unlock >/dev/null 2>&1 || true

# --- connectivity / repo precheck: fail clean, no partial state ---
if ! restic snapshots >/dev/null 2>&1; then
  log "ERROR: repository unreachable (no internet, or auth/repo problem); aborting"
  exit 1
fi

log "=== backup start ==="
set +e
restic backup /home \
  --exclude-file="$EXCLUDES" \
  --exclude-caches \
  --verbose 2>&1 | tee -a "$LOG"
rc=${PIPESTATUS[0]}
set -e

# restic exit codes: 0 ok, 3 = snapshot made but some files were unreadable.
if [[ "$rc" -eq 0 ]]; then
  log "backup completed OK"
elif [[ "$rc" -eq 3 ]]; then
  log "WARNING: backup completed but some files were unreadable (rc=3)"
else
  log "FATAL: backup failed (rc=$rc)"; exit "$rc"
fi

log "=== forget + prune (retention) ==="
restic forget --prune \
  --keep-last 3 \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 12 2>&1 | tee -a "$LOG"

log "=== done ==="
