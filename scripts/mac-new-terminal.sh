#!/bin/sh
# Open a new Terminal.app window in the existing instance.
# `open -n -a Terminal` starts a second Terminal process, which restores old
# sessions (the "[Restored …]" banner and leftover scrollback).
exec /usr/bin/osascript <<'EOF'
tell application "Terminal"
  if it is running then
    do script ""
  else
    activate
  end if
end tell
EOF
