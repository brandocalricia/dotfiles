#!/usr/bin/env bash
# Desktop banner when Grok finishes a turn — unless the user is already
# looking at *this* session's window.
#
# Rules:
#   - Notify if another app is focused (YouTube, browser, etc.)
#   - Notify if another Terminal/Grok window or tab is focused
#   - Notify if this session is on a different AeroSpace workspace
#   - Do NOT notify if this session's Terminal tab is the focused window
#   - Two Grok sessions finishing near each other both notify (per-tty lock)
#   - Stop + task_complete for the SAME session is debounced (~2s)
#   - Fail open: if we cannot prove this window is focused, notify
#
# GROK_NOTIFY_FORCE=1 skips the focus check (manual tests).
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

norm_tty() {
  echo "$1" | tr -d ' \r' | sed 's|^/dev/||'
}

# Controlling tty of THIS grok session. The hook itself has stdin=JSON and
# often no tty; walk parents until we hit grok/zsh on a real ttys.
session_tty() {
  if [ -n "${GROK_TTY:-}" ]; then
    echo "$GROK_TTY"
    return
  fi
  python3 - <<'PY'
import os, subprocess, sys

def tty_of(pid: int) -> str:
    try:
        t = subprocess.check_output(["ps", "-o", "tty=", "-p", str(pid)], text=True).strip()
    except Exception:
        return ""
    if not t or t in ("??", "?"):
        return ""
    return t if t.startswith("/") else "/dev/" + t

pid = os.getppid()
seen = set()
while pid and pid > 1 and pid not in seen:
    seen.add(pid)
    t = tty_of(pid)
    if t:
        print(t)
        sys.exit(0)
    try:
        pid = int(subprocess.check_output(["ps", "-o", "ppid=", "-p", str(pid)], text=True).strip())
    except Exception:
        break
PY
}

ours=$(session_tty || true)
ours_n=$(norm_tty "${ours:-}")
lock_key="${ours_n:-pid$$}"
lock="${TMPDIR:-/tmp}/grok-done-notify-${UID:-user}-${lock_key}"
now=$(date +%s)
if [ -f "$lock" ]; then
  prev=$(cat "$lock" 2>/dev/null || echo 0)
  if [ "${prev:-0}" -ge $((now - 2)) ] 2>/dev/null; then
    exit 0
  fi
fi
echo "$now" > "$lock" 2>/dev/null || true

# Skip only when we can prove this session's tab is what they are looking at.
this_session_is_focused() {
  [ -n "${GROK_NOTIFY_FORCE:-}" ] && return 1
  [ -n "$ours_n" ] || return 1

  local app=""
  if command -v aerospace >/dev/null 2>&1; then
    app=$(aerospace list-windows --focused --format '%{app-name}' 2>/dev/null | head -1 | tr -d '\r')
  fi
  if [ -z "$app" ]; then
    app=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null || true)
  fi
  app=$(echo "$app" | tr -d '\r')
  case "$app" in
    Terminal) ;;
    *) return 1 ;;
  esac

  local front=""
  front=$(osascript -e 'tell application "Terminal"
    if not (exists front window) then return ""
    return tty of selected tab of front window
  end tell' 2>/dev/null || true)
  front=$(norm_tty "$front")
  [ -n "$front" ] && [ "$front" = "$ours_n" ]
}

if this_session_is_focused; then
  exit 0
fi

title="Grok"
here=$(pwd -P 2>/dev/null || pwd)
here="${here/#$HOME/~}"
msg="Finished responding"
[ -n "$here" ] && msg="Finished responding  ·  $here"

if [ "$(uname -s)" = Darwin ]; then
  # Terminal.app is not a notification provider. Helper app posts as "Grok".
  app="${HOME}/Applications/Grok.app"
  bin="$app/Contents/MacOS/GrokNotify"
  if [ ! -x "$bin" ]; then
    "$(dirname "$0")/build-grok-notify-app.sh" >/dev/null 2>&1 || true
  fi
  if [ -x "$bin" ]; then
    "$bin" "$title" "$msg" >/dev/null 2>&1 &
  fi
elif command -v notify-send >/dev/null 2>&1; then
  notify-send -u normal -t 6000 "$title" "$msg" >/dev/null 2>&1 || true
fi
exit 0
