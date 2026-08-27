#!/usr/bin/env bash
# Isolated dry-run of captive-portal-watch.sh with a fake nmcli.
# Does not touch live NetworkManager or spawn a browser.
set -euo pipefail

WATCHER="${WATCHER:-$HOME/.config/hypr/captive-portal-watch.sh}"
[ -x "$WATCHER" ] || WATCHER="$HOME/dotfiles/hypr/.config/hypr/captive-portal-watch.sh"
[ -x "$WATCHER" ] || { echo "watcher not found" >&2; exit 1; }

STUB_DIR=$(mktemp -d)
LOG=$(mktemp)
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf 'OK    %s\n' "$*"; }
bad(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$*"; }

cleanup() { rm -rf "$STUB_DIR" "$LOG"; }
trap cleanup EXIT

cat > "$STUB_DIR/nmcli" << 'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "networking" ] && [ "${2:-}" = "connectivity" ]; then
  printf '%s\n' "${FAKE_SEED:-full}"
  exit 0
fi
if [ "${1:-}" = "monitor" ]; then
  if [ -n "${FAKE_EVENTS:-}" ] && [ -f "${FAKE_EVENTS}" ]; then
    cat "$FAKE_EVENTS"
  fi
  exec sleep 60
fi
exit 1
EOF
chmod +x "$STUB_DIR/nmcli"

run_case() {
  local name="$1" seed="$2" events="$3" expect_open="$4"
  : > "$LOG"
  local ev
  ev=$(mktemp)
  for st in $events; do
    printf "Connectivity is now '%s'\n" "$st" >> "$ev"
  done

  FAKE_SEED="$seed" FAKE_EVENTS="$ev" \
    PATH="$STUB_DIR:$PATH" \
    CAPTIVE_PORTAL_DRYRUN=1 \
    CAPTIVE_PORTAL_LOCK=none \
    CAPTIVE_PORTAL_LOG="$LOG" \
    timeout 2 bash "$WATCHER" >/dev/null 2>&1 || true
  rm -f "$ev"

  local opens
  opens=$(grep -c 'DRYRUN portal detected' "$LOG" || true)
  if [ "$opens" -eq "$expect_open" ]; then
    ok "$name (opens=$opens)"
  else
    bad "$name expected $expect_open opens, got $opens"
    sed 's/^/      /' "$LOG"
  fi
}

echo "watcher: $WATCHER"
run_case "full seed, no events"            full   ""                    0
run_case "already portal at seed"          portal ""                    1
run_case "full -> portal"                  full   "portal"              1
run_case "full -> portal -> full"          full   "portal full"         1
run_case "re-arm portal->full->portal"     full   "portal full portal"  2
run_case "dup portal does not re-fire"     full   "portal portal"       1
run_case "none/limited ignored"            full   "none limited full"   0

echo "WATCHER SCORE PASS=$PASS FAIL=$FAIL"
exit "$FAIL"
