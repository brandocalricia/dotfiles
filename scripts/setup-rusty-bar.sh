#!/usr/bin/env bash
# setup-rusty-bar.sh — one-time, per-machine setup for the Rusty's Retirement
# docked bar. Run ONCE on any new host (e.g. the laptop) after installing the game
# from Steam. The Hyprland side (window rules + rusty-bar-watch.sh) already syncs
# via dotfiles; this handles the Steam side, which does NOT sync (Proton binaries
# and per-machine Steam config live outside dotfiles):
#   1. installs gamescope (dnf) if missing
#   2. installs GE-Proton11-1 into compatibilitytools.d if missing
#   3. maps the game to GE-Proton11-1 (config.vdf)
#   4. sets the launch option to run it through gamescope (localconfig.vdf)
#
# Idempotent and safe to re-run. Backs up the Steam .vdf files it edits.
set -euo pipefail

APPID=2666510
GE_VER="GE-Proton11-1"
LAUNCH_OPT='~/.config/hypr/rusty-launch.sh %command%'

log(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m!  \033[0m %s\n' "$*"; }

# --- locate Steam root (native install) ---
STEAM_ROOT=""
for d in "$HOME/.steam/root" "$HOME/.local/share/Steam" "$HOME/.steam/steam"; do
  [ -d "$d/steamapps" ] && { STEAM_ROOT="$d"; break; }
done
[ -n "$STEAM_ROOT" ] || { warn "Could not find a native Steam install. Is Steam installed (not Flatpak)?"; exit 1; }
log "Steam root: $STEAM_ROOT"

# --- 1. gamescope ---
if command -v gamescope >/dev/null 2>&1; then
  log "gamescope already installed"
else
  log "Installing gamescope (needs sudo)…"
  sudo dnf install -y --exclude=gdm gamescope
fi

# --- 2. GE-Proton11-1 ---
COMPAT="$STEAM_ROOT/compatibilitytools.d"
mkdir -p "$COMPAT"
if [ -d "$COMPAT/$GE_VER" ]; then
  log "$GE_VER already present"
else
  log "Downloading $GE_VER (~500 MB)…"
  tmp="$(mktemp -d)"
  base="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/$GE_VER"
  curl -fL# -o "$tmp/$GE_VER.tar.gz"      "$base/$GE_VER.tar.gz"
  curl -fL  -o "$tmp/$GE_VER.sha512sum"   "$base/$GE_VER.sha512sum"
  ( cd "$tmp" && sha512sum -c "$GE_VER.sha512sum" ) || { warn "checksum failed"; exit 1; }
  tar -xzf "$tmp/$GE_VER.tar.gz" -C "$COMPAT"
  rm -rf "$tmp"
  log "Installed $GE_VER"
fi

# --- Steam must be closed before editing its .vdf files ---
if pgrep -x steam >/dev/null 2>&1; then
  log "Shutting down Steam to edit its config…"
  steam -shutdown >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
fi

# --- 3. Proton mapping in config.vdf ---
CFG="$STEAM_ROOT/config/config.vdf"
if [ -f "$CFG" ]; then
  cp "$CFG" "$CFG.rustybak"
  APPID="$APPID" GE_VER="$GE_VER" python3 - "$CFG" <<'PY'
import os,re,sys
p=sys.argv[1]; appid=os.environ["APPID"]; ge=os.environ["GE_VER"]
lines=open(p,newline="").read().split("\n")
i=next((k for k,l in enumerate(lines) if l.strip()=='"CompatToolMapping"'),None)
if i is None: print("!  CompatToolMapping not found; skipping mapping"); sys.exit()
depth=0; close=None
for j in range(i+1,len(lines)):
    depth+=lines[j].count("{")-lines[j].count("}")
    if depth==0: close=j; break
ki=re.match(r'^(\s*)',lines[i+2]).group(1); fi=ki+"\t"
sec="\n".join(lines[i:close+1])
if f'"{appid}"' in sec:
    # rewrite existing block's name
    out=[]; d=0; inblk=False
    for j in range(i,close+1):
        l=lines[j]
        if l.strip()==f'"{appid}"': inblk=True
        if inblk and '"name"' in l:
            l=f'{fi}"name"\t\t"{ge}"'; inblk=False
        out.append((j,l))
    for j,l in out: lines[j]=l
    print(f"==> updated {appid} -> {ge}")
else:
    blk=[f'{ki}"{appid}"',f'{ki}{{',f'{fi}"name"\t\t"{ge}"',f'{fi}"config"\t\t""',f'{fi}"priority"\t\t"250"',f'{ki}}}']
    lines[close:close]=blk
    print(f"==> mapped {appid} -> {ge}")
open(p,"w",newline="").write("\n".join(lines))
PY
else
  warn "config.vdf not found; set Proton to $GE_VER manually in the game's Compatibility settings"
fi

# --- 4. launch option in localconfig.vdf ---
LC="$(ls "$STEAM_ROOT"/userdata/*/config/localconfig.vdf 2>/dev/null | head -1 || true)"
if [ -n "$LC" ]; then
  cp "$LC" "$LC.rustybak"
  APPID="$APPID" OPT="$LAUNCH_OPT" python3 - "$LC" <<'PY'
import os,re,sys
p=sys.argv[1]; appid=os.environ["APPID"]; opt=os.environ["OPT"]
lines=open(p,newline="").read().split("\n")
# app config block: "<appid>" whose block has LastPlayed
bo=None
for i,l in enumerate(lines):
    if l.strip()==f'"{appid}"' and i+1<len(lines) and lines[i+1].strip()=="{":
        d=0
        for j in range(i+1,min(i+80,len(lines))):
            d+=lines[j].count("{")-lines[j].count("}")
            if "LastPlayed" in lines[j] or "Playtime" in lines[j]: bo=i
            if d==0: break
        if bo is not None: break
if bo is None: print("!  app block not found; set the launch option manually"); sys.exit()
ind=re.match(r'^(\s*)',lines[bo+2]).group(1)
# drop any existing LaunchOptions in the block
d=0; out=[]
for j in range(bo+1,len(lines)):
    d+=lines[j].count("{")-lines[j].count("}")
    if lines[j].strip().startswith('"LaunchOptions"'):
        pass
    else:
        out.append((j,lines[j]))
    if d==0: end=j; break
# rebuild block region without LaunchOptions, then insert fresh one
newblock=[lines[bo],lines[bo+1]]  # "appid" and {
kept=[l for (j,l) in out if j>bo+1]
newblock+= [f'{ind}"LaunchOptions"\t\t"{opt}"'] + kept
lines[bo:end+1]=newblock
open(p,"w",newline="").write("\n".join(lines))
print("==> set launch option:",opt)
PY
else
  warn "localconfig.vdf not found; set the launch option manually to: $LAUNCH_OPT"
fi

log "Done. Start Steam, launch Rusty's Retirement — it will dock to the bottom of workspace 1."
