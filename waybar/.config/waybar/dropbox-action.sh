#!/usr/bin/env bash
# Actions for the Waybar Dropbox menu (Mac-style menubar analog).
export PATH="/usr/bin:/bin:/usr/local/bin:${HOME}/.local/bin:${PATH}"
set -uo pipefail

DROPBOX="${HOME}/.local/bin/dropbox"
FOLDER="${HOME}/Dropbox"
ACTION="${1:-}"

refresh() {
    pkill -RTMIN+10 -x waybar 2>/dev/null || true
}

notify() {
    notify-send -a Dropbox -u low -- "Dropbox" "$1"
}

open_url() {
    xdg-open "$1" >/dev/null 2>&1 || true
}

list_recent() {
    find "$FOLDER" -type f \
        ! -path '*/.dropbox.cache/*' \
        ! -path '*/.git/*' \
        ! -path '*/.obsidian/plugins/*' \
        ! -path '*/.obsidian/themes/*' \
        ! -name '.DS_Store' \
        ! -name '.dropbox' \
        -printf '%T@\t%P\n' 2>/dev/null \
        | sort -nr \
        | head -20 \
        | cut -f2-
}

pick_recent() {
    local prompt="$1"
    local choice
    choice=$(list_recent | fuzzel --dmenu --prompt "${prompt} " --width 80 --lines 16 --minimal-lines) || true
    [[ -n "${choice:-}" ]] || return 1
    printf '%s\n' "$choice"
}

case "$ACTION" in
    open-folder)
        mkdir -p "$FOLDER"
        xdg-open "$FOLDER" >/dev/null 2>&1 || true
        ;;
    open-web)
        open_url "https://www.dropbox.com/home"
        ;;
    account)
        open_url "https://www.dropbox.com/account"
        ;;
    help)
        open_url "https://help.dropbox.com"
        ;;
    pause)
        systemctl --user stop dropbox.service
        refresh
        notify "Syncing paused"
        ;;
    resume)
        systemctl --user start dropbox.service
        refresh
        notify "Syncing resumed"
        ;;
    restart)
        systemctl --user restart dropbox.service
        refresh
        notify "Dropbox restarted"
        ;;
    recent)
        rel=$(pick_recent "Recent Dropbox") || exit 0
        xdg-open "${FOLDER}/${rel}" >/dev/null 2>&1 || true
        ;;
    sharelink)
        rel=$(pick_recent "Copy shared link") || exit 0
        url=$(timeout 15 "$DROPBOX" sharelink "${FOLDER}/${rel}" 2>/dev/null || true)
        if [[ -z "${url:-}" ]]; then
            notify "Could not create a shared link for ${rel}"
            exit 1
        fi
        printf '%s' "$url" | wl-copy
        notify "Copied shared link for ${rel}"
        ;;
    link)
        if timeout 5 "$DROPBOX" status 2>/dev/null | grep -qi 'up to date\|syncing\|connecting'; then
            notify "Already linked"
            exit 0
        fi
        url=$(journalctl --user -u dropbox.service -n 80 --no-pager \
            | grep -o 'https://www.dropbox.com/cli_link_nonce?nonce=[A-Za-z0-9]*' \
            | tail -1)
        if [[ -z "${url:-}" ]]; then
            notify "No link URL yet — is Dropbox running?"
            exit 1
        fi
        open_url "$url"
        ;;
    *)
        echo "usage: $0 {open-folder|open-web|account|help|pause|resume|restart|recent|sharelink|link}" >&2
        exit 2
        ;;
esac
