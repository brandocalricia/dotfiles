#!/usr/bin/env bash
# Desktop banner when Grok finishes a turn.
# Wired as a Stop + Notification(task_complete) hook. Debounced so both
# firing for one turn does not double-ping. Never blocks the stop (exit 0,
# no JSON). Session teardown and cancelled turns stay quiet.
set -u

payload=""
if [ ! -t 0 ]; then
  payload=$(cat || true)
fi

event="${GROK_HOOK_EVENT:-}"
case "$event" in
  StopCancelled|SessionEnd|StopFailure) exit 0 ;;
esac

reason=""
if [ -n "$payload" ]; then
  reason=$(printf '%s' "$payload" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
print(d.get("reason") or d.get("notificationType") or d.get("type") or "")
' 2>/dev/null || true)
fi

case "$reason" in
  channel_closed|shutdown|user_interrupt|permission_rejected|permission_cancelled|max_turns|no_progress)
    exit 0
    ;;
esac

# Stop also fires at session end with reason=end_turn sometimes; debounce covers it.
lock="${TMPDIR:-/tmp}/grok-done-notify-${UID:-user}"
now=$(date +%s)
if [ -f "$lock" ]; then
  prev=$(cat "$lock" 2>/dev/null || echo 0)
  if [ "${prev:-0}" -ge $((now - 5)) ] 2>/dev/null; then
    exit 0
  fi
fi
echo "$now" > "$lock" 2>/dev/null || true

title="Grok"
msg="Finished responding"

if [ "$(uname -s)" = Darwin ]; then
  osascript -e "display notification \"${msg}\" with title \"${title}\" sound name \"Glass\"" >/dev/null 2>&1 || true
elif command -v notify-send >/dev/null 2>&1; then
  notify-send -u normal -t 6000 "$title" "$msg" >/dev/null 2>&1 || true
fi
exit 0
