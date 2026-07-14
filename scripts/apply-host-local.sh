#!/usr/bin/env bash
# apply-host-local.sh — point the bare per-host config files (which the shared
# configs `include`/`source`) at THIS machine's tracked, hostname-namespaced file.
#
# Why: waybar/config.jsonc includes ~/.config/waybar/local.jsonc and
# hyprland.conf sources ~/.config/hypr/local.conf. Those bare names are
# gitignored (each host needs a different one). We instead TRACK the real
# content as local.<hostname>.jsonc / local.<hostname>.conf so every machine's
# config lives in the repo and is visible to the others, then symlink the bare
# name at the host file. New machine with no file yet? Seed it from .example.
#
# Idempotent. Safe to run repeatedly. No sudo. Run after `stow`/on install and
# any time you switch what the host file is called.
set -euo pipefail

host="$(hostnamectl --static 2>/dev/null || hostname)"
host="${host:-$(hostname)}"

link_host() {
  local dir="$1" bare="$2" ext="$3"
  local hostfile="local.${host}.${ext}"
  local example="local.${ext}.example"

  if [ ! -e "${dir}/${hostfile}" ]; then
    if [ -e "${dir}/${bare}" ] && [ ! -L "${dir}/${bare}" ]; then
      # First migration: an existing real bare file becomes this host's file.
      cp "${dir}/${bare}" "${dir}/${hostfile}"
      echo "migrated ${dir}/${bare} -> ${hostfile} (tracked)"
    else
      cp "${dir}/${example}" "${dir}/${hostfile}"
      echo "seeded  ${dir}/${hostfile} from ${example} (edit it, then it auto-commits)"
    fi
  fi

  ln -sfn "${hostfile}" "${dir}/${bare}"   # relative link, portable across machines
  echo "linked  ${dir}/${bare} -> ${hostfile}"
}

link_host "${HOME}/.config/waybar" "local.jsonc" "jsonc"
link_host "${HOME}/.config/hypr"   "local.conf"  "conf"

echo "done. host = ${host}"
