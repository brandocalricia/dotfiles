#!/usr/bin/env bash
# Waybar JSON for the Dropbox chip. Icon-only; details live in the tooltip.
export PATH="/usr/bin:/bin:/usr/local/bin:${HOME}/.local/bin:${PATH}"
set -uo pipefail

ICON=""
DROPBOX="${HOME}/.local/bin/dropbox"
FOLDER="${HOME}/Dropbox"

emit() {
    local class="$1"
    local tooltip="$2"
    python3 -c 'import json,sys; print(json.dumps({"text":sys.argv[1],"class":sys.argv[2],"tooltip":sys.argv[3],"alt":sys.argv[2]}, ensure_ascii=False))' \
        "$ICON" "$class" "$tooltip"
}

fail() {
    emit error "Dropbox"$'\n'"status unavailable"
    exit 0
}

unit=$(systemctl --user is-active dropbox.service 2>/dev/null || echo inactive)

if [[ "$unit" != "active" ]]; then
    case "$unit" in
        activating|reloading)
            emit starting "Dropbox"$'\n'"Starting…"
            ;;
        failed)
            emit error "Dropbox"$'\n'"Service failed"$'\n'"Click to open the menu"
            ;;
        *)
            emit paused "Dropbox paused"$'\n'"Not syncing"$'\n'"Click the icon → Resume Syncing"
            ;;
    esac
    exit 0
fi

raw=$(timeout 5 "$DROPBOX" status 2>/dev/null || true)
raw=${raw%%$'\n'}
if [[ -z "$raw" ]]; then
    fail
fi

lower=$(printf '%s\n' "$raw" | tr '[:upper:]' '[:lower:]')
tooltip="Dropbox"$'\n'"${raw}"$'\n'$'\n'"${FOLDER}"

case "$lower" in
    *"isn't running"*)
        emit paused "Dropbox"$'\n'"Daemon not running"$'\n'"Click the icon → Resume Syncing"
        ;;
    *"isn't linked"*|*"not linked"*|*cli_link_nonce*|*starting...*)
        emit error "Dropbox"$'\n'"${raw}"$'\n'"Click the icon → Link This Computer"
        ;;
    *"up to date"*)
        emit synced "$tooltip"
        ;;
    *syncing*|*download*|*upload*|*index*|*connecting*)
        emit syncing "$tooltip"
        ;;
    *)
        emit syncing "$tooltip"
        ;;
esac
