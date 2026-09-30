#!/usr/bin/env bash
# If Hyprland stops answering, the windows freeze while the kernel and
# user services keep running (a TTY can still log in). Kill the compositor
# so greetd returns to the login screen. If Hyprland is stuck in the GPU
# driver and SIGKILL cannot reap it, ask the root helper to sync and reboot.
set -u
log="${HOME}/.local/state/hypr-unfreeze.log"
mkdir -p "${HOME}/.local/state"
fail=0

logm() {
  printf '%s %s\n' "$(date -Is)" "$*" >> "$log"
  logger -t hypr-unfreeze -- "$*" || true
}

boottime() {
  /usr/bin/python3 -c 'import time; print(int(time.clock_gettime(time.CLOCK_BOOTTIME)))'
}

prev=$(boottime)
while true; do
  sleep 3
  now=$(boottime)
  gap=$((now - prev))
  prev=$now
  # Suspend freezes this process. A long gap is a wake, not a wedge.
  if [ "$gap" -gt 12 ]; then
    fail=0
    continue
  fi

  pid=$(pidof -s Hyprland || true)
  if [ -z "$pid" ]; then
    exit 0
  fi

  /usr/bin/hyprctl version >/dev/null 2>&1 &
  probe=$!
  answered=0
  for _ in 1 2 3 4; do
    if ! kill -0 "$probe" 2>/dev/null; then
      answered=1
      break
    fi
    sleep 0.5
  done
  if [ "$answered" -eq 1 ]; then
    wait "$probe" || true
    fail=0
    continue
  fi
  # Do not wait: a probe blocked in the GPU driver will not die on SIGKILL.
  kill -KILL "$probe" 2>/dev/null || true
  fail=$((fail + 1))
  logm "hyprctl did not answer (${fail})"
  if [ "$fail" -lt 4 ]; then
    continue
  fi

  logm "compositor wedged; stopping Hyprland pid ${pid}"
  kill -TERM "$pid" 2>/dev/null || true
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null || true
    sleep 3
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    logm "Hyprland stopped; greetd should return to the login screen"
    exit 0
  fi

  logm "Hyprland ${pid} stuck in the driver; requesting reboot"
  if sudo -n /usr/local/sbin/unfreeze-reboot; then
    exit 0
  fi
  logm "reboot helper unavailable; hold Alt+PrintScreen and type REISUB slowly"
  exit 0
done
