#!/usr/bin/env bash
# setup-balatro-mods.sh — install/refresh the Balatro mod stack for the Steam
# (Proton) build, app 2379780. Per-machine, idempotent, no sudo.
#
# Mirrors the desktop (brandon-fedora) setup so the laptop (fedora) matches.
# Re-derives all paths at runtime — do NOT hardcode a drive; the laptop's Steam
# library and build (RPM vs Flatpak) may differ from the desktop's.
#
# What it does NOT do (Steam UI, can't be scripted):
#   * Set launch options. You must set Balatro -> Properties -> Launch Options to:
#       WINEDLLOVERRIDES="version=n,b" %command%
#   * That's what makes Proton load Lovely's version.dll. Without it, nothing loads.
#
# Usage:  ~/dotfiles/scripts/setup-balatro-mods.sh
# Update: bump the pinned versions in LOVELY_VER / MODS below, re-run.
set -euo pipefail

APPID=2379780
LOVELY_VER="v0.9.0"   # ethangreen-dev/lovely-injector — Windows build (runs under Proton)

# name | download URL  (codeload src-zip for repos w/o a built asset; branch zip where no release)
MODS=(
  "smods|https://codeload.github.com/Steamodded/smods/zip/refs/tags/1.0.0-beta-1814a"
  "Talisman|https://codeload.github.com/SpectralPack/Talisman/zip/refs/tags/v2.7"
  "MoreFluff|https://github.com/notmario/MoreFluff/releases/download/1.6.0-rc3/MoreFluff.zip"
  "AllInJest|https://codeload.github.com/survovoaneend/All-In-Jest/zip/refs/tags/0.6.6b"
  "Bunco|https://codeload.github.com/jumbocarrot0/Bunco/zip/refs/tags/v5.4.8b-JumboFork"
  "JokerDisplay|https://codeload.github.com/nh6574/JokerDisplay/zip/refs/tags/v1.10.7"
  "Cartomancer|https://github.com/stupxd/Cartomancer/releases/download/v4.17c/Cartomancer-v4.17c.zip"
  "Handy|https://github.com/SleepyG11/HandyBalatro/releases/download/v1.5.1p/Handy-v1.5.1p.zip"
  "Incantation|https://codeload.github.com/stupxd/Incantation/zip/refs/heads/main"
  "Nopeus|https://codeload.github.com/stupxd/Nopeus/zip/refs/heads/main"
  "DebugPlus|https://github.com/WilsontheWolf/DebugPlus/releases/download/v1.5.3/DebugPlus.zip"
)

die() { echo "ERROR: $*" >&2; exit 1; }
say() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

# --- 0. locate Steam root, game dir, save/prefix dir -------------------------
find_game() {
  local roots=(
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
  )
  for root in "${roots[@]}"; do
    local vdf="$root/steamapps/libraryfolders.vdf"
    [ -f "$vdf" ] || continue
    # every library path listed in the vdf, plus the root itself
    local libs
    libs=$(grep -oE '"path"[[:space:]]+"[^"]+"' "$vdf" | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/')
    while IFS= read -r lib; do
      [ -n "$lib" ] || continue
      local g="$lib/steamapps/common/Balatro"
      if [ -f "$g/Balatro.exe" ]; then
        GAME_DIR="$g"
        SAVE_DIR="$lib/steamapps/compatdata/$APPID/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro"
        STEAM_ROOT="$root"
        return 0
      fi
    done <<< "$libs"$'\n'"$root"
  done
  return 1
}

find_game || die "Balatro (app $APPID) not found. Install it in Steam and run it once, then re-run this."
[ -d "$SAVE_DIR" ] || die "Save/prefix dir missing: $SAVE_DIR
Launch the game once (so Proton creates the prefix), then re-run."

say "Steam root : $STEAM_ROOT"
say "Game dir   : $GAME_DIR"
say "Save dir   : $SAVE_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 1. Lovely injector (version.dll into the game dir) ----------------------
say "Installing Lovely injector $LOVELY_VER"
curl -fsSL -o "$TMP/lovely.zip" \
  "https://github.com/ethangreen-dev/lovely-injector/releases/download/$LOVELY_VER/lovely-x86_64-pc-windows-msvc.zip"
unzip -oq -j "$TMP/lovely.zip" version.dll -d "$GAME_DIR"
[ -f "$GAME_DIR/version.dll" ] || die "version.dll did not land in the game dir"

# --- 2. Mods folder (back up any existing real content) ----------------------
MODS_DIR="$SAVE_DIR/Mods"
mkdir -p "$MODS_DIR"

# --- 3. install each mod, auto-detecting the real mod root -------------------
# The mod root is the SHALLOWEST dir containing a Steamodded manifest:
#   a *.json with "id"+"prefix", OR a *.lua/.toml carrying a STEAMODDED HEADER.
# This survives version bumps (wrapper folder names change with the tag).
mod_root() {
  local base="$1" best="" bestdepth=9999 f d depth
  while IFS= read -r f; do
    d=$(dirname "$f"); depth=$(awk -F/ '{print NF}' <<< "$d")
    if [ "$depth" -lt "$bestdepth" ]; then best="$d"; bestdepth=$depth; fi
  done < <(
    grep -rlE '"id"[[:space:]]*:' "$base" --include='*.json' 2>/dev/null
    grep -rlE 'STEAMODDED HEADER' "$base" --include='*.lua' 2>/dev/null
  )
  [ -n "$best" ] && { echo "$best"; return 0; }
  return 1
}

for entry in "${MODS[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  say "Installing $name"
  work="$TMP/$name"; mkdir -p "$work"
  curl -fsSL -o "$work.zip" "$url"
  unzip -q "$work.zip" -d "$work"
  src=$(mod_root "$work") || die "no Steamodded manifest found in $name archive"
  dest="$MODS_DIR/$name"
  rm -rf "$dest"; mkdir -p "$dest"
  cp -a "$src"/. "$dest"/
done

# --- 4. permissions (archives carry Windows bits) ----------------------------
say "Fixing permissions (755 dirs / 644 files)"
find "$MODS_DIR" -type d -exec chmod 755 {} +
find "$MODS_DIR" -type f -exec chmod 644 {} +

# --- 5. report ---------------------------------------------------------------
echo
say "Done. Installed under: $MODS_DIR"
ls -1 "$MODS_DIR" | grep -v '^lovely$' | sed 's/^/    /'
cat <<EOF

NEXT (Steam UI — cannot be scripted):
  1. Steam -> Balatro -> Properties -> General -> Launch Options:
       WINEDLLOVERRIDES="version=n,b" %command%
  2. Launch. A second "Lovely v..." console window should appear.
  3. Main menu should show a MODS button. Click it to confirm the list.
  4. Switch to PROFILE 2 before playing, so a mod crash can't touch vanilla unlocks.

Uninstall everything:   rm "$GAME_DIR/version.dll"   (disables all mods; leaves them on disk)
Remove mods too:        rm -rf "$MODS_DIR"
EOF
