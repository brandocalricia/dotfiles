#!/usr/bin/env bash
# install-atuin-latest.sh — put the latest atuin client in ~/.local/bin.
# The Fedora package lags (18.12.1) and is too old to register/sync against the
# public server (the old registration endpoint was retired). ~/.local/bin is
# ahead of /usr/bin on PATH, so this wins without removing the package.
# User scope, no sudo. Idempotent.
set -uo pipefail

want=$(curl -fsSL https://api.github.com/repos/atuinsh/atuin/releases/latest 2>/dev/null \
        | jq -r '.tag_name' 2>/dev/null | sed 's/^v//')
have=$( ~/.local/bin/atuin --version 2>/dev/null | awk '{print $2}')
if [ -n "$want" ] && [ "$want" = "$have" ]; then
  echo "[=] atuin $have already latest in ~/.local/bin"; exit 0
fi

url=$(curl -fsSL https://api.github.com/repos/atuinsh/atuin/releases/latest 2>/dev/null \
       | jq -r '.assets[] | select(.name=="atuin-x86_64-unknown-linux-gnu.tar.gz") | .browser_download_url')
[ -z "$url" ] && { echo "[!] couldn't find atuin release asset"; exit 1; }

tmp=$(mktemp -d); mkdir -p ~/.local/bin
curl -fsSL "$url" -o "$tmp/a.tar.gz" && tar xzf "$tmp/a.tar.gz" -C "$tmp" \
  && find "$tmp" -type f -name atuin -exec install -m755 {} ~/.local/bin/atuin \; \
  && echo "[+] atuin $(~/.local/bin/atuin --version | awk '{print $2}') installed to ~/.local/bin"
rm -rf "$tmp"
