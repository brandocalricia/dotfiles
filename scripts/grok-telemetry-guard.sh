#!/usr/bin/env bash
# grok-telemetry-guard.sh — fail loud if session-trace upload can fire.
# Run after grok updates (path unit on the binary) and from SessionStart.
set -uo pipefail

BIN="${GROK_BIN:-$HOME/.grok/downloads/grok-linux-x86_64}"
CFG="${GROK_HOME:-$HOME/.grok}/config.toml"
ALERT="${GROK_HOME:-$HOME/.grok}/rules/telemetry-alert.md"
STATUS="$HOME/.cache/brain-hooks/telemetry-guard.txt"
mkdir -p "$(dirname "$ALERT")" "$HOME/.cache/brain-hooks"

fail() {
  msg=$1
  printf '%s\n' "GROK TELEMETRY GUARD FAIL: $msg" >&2
  printf '%s\n' "# GROK TELEMETRY GUARD FAIL
Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)

**$msg**

This file is loaded as a home rule so it cannot hide. Fix:
- \`[features] telemetry = false\` and \`[telemetry] trace_upload = false\` in $CFG
- re-run \`$HOME/dotfiles/scripts/grok-telemetry-guard.sh\`
" > "$ALERT"
  printf '%s\n' "FAIL $msg" > "$STATUS"
  # visible on a graphical session; ignore if no bus
  command -v notify-send >/dev/null 2>&1 && notify-send -u critical "Grok telemetry guard" "$msg" || true
  exit 1
}

ok() {
  rm -f "$ALERT"
  printf '%s\n' "OK $*" > "$STATUS"
  printf '%s\n' "GROK TELEMETRY GUARD OK: $*"
  exit 0
}

[ -f "$BIN" ] || fail "binary missing at $BIN"
[ -f "$CFG" ] || fail "config missing at $CFG"

needles="grok-code-session-traces GROK_TELEMETRY_GCS_BUCKET GROK_TRACE_UPLOAD_BUCKET"
hits=""
for n in $needles; do
  if grep -a -q -F "$n" "$BIN" 2>/dev/null; then
    hits="$hits $n"
  fi
done
[ -n "$hits" ] || fail "expected leak-path strings missing from binary — inspect the new version"

# Local kill switches must be explicit false, not absent.
tel=$(grep -E '^telemetry\s*=' "$CFG" | tail -1 | awk '{print $3}')
tru=$(grep -E '^trace_upload\s*=' "$CFG" | tail -1 | awk '{print $3}')
[ "$tel" = "false" ] || fail "[features] telemetry is '$tel' (want false) in $CFG"
[ "$tru" = "false" ] || fail "[telemetry] trace_upload is '$tru' (want false) in $CFG"

# Effective resolution from a one-shot inspect of recent logs if present.
# Do not start grok just to check — that would recurse on SessionStart.
ok "needles still in binary ($hits); local telemetry=false trace_upload=false"