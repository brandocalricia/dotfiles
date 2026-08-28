#!/usr/bin/env bash
# Build ~/Applications/Grok.app — a real bundle so macOS Notification Center
# has something to list (Terminal.app never appears there).
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || exit 0

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)/mac"
APP="${HOME}/Applications/Grok.app"
BIN="$APP/Contents/MacOS/GrokNotify"
PLIST="$APP/Contents/Info.plist"

mkdir -p "$HOME/Applications" "$APP/Contents/MacOS"
cp "$SRC_DIR/GrokNotify-Info.plist" "$PLIST"
xattr -cr "$APP" 2>/dev/null || true
swiftc -O -o "$BIN" \
  -framework AppKit -framework UserNotifications \
  "$SRC_DIR/GrokNotify.swift"
chmod +x "$BIN"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
