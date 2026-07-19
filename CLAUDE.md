# CLAUDE.md — dotfiles operational notes

Short, factual notes so a future session can redo things fast. Deep setup/disaster
docs live in `SETUP-NOTES.md`; this file is the "how it's wired now" quick reference.

## Config sync system (both machines)

**Goal:** every machine's config lives in the repo and auto-syncs, so either host
can see + reuse the other's setup (this was added after the laptop couldn't see the
desktop's waybar `local.jsonc`).

- **Deploy model:** stow folds at the **directory** level — `~/.config/hypr` and
  `~/.config/waybar` are symlinks INTO the repo (`readlink ~/.config/hypr` →
  `../dotfiles/hypr/.config/hypr`). So **editing live config IS editing the repo**
  (same inode); there is no copy step and no drift. Files inside read as regular
  files but are the repo files.
- **Per-host config is tracked, namespaced by hostname.** The shared configs
  include the bare `local.conf` / `local.jsonc`, which are host-selected **symlinks**
  → this host's tracked `local.<hostname>.{conf,jsonc}` (laptop hostname `fedora`,
  desktop `brandon-fedora`). Bare names stay gitignored; `local.<host>.*` are
  committed. Resolver: `scripts/apply-host-local.sh` (idempotent; run by install.sh
  after stow; seeds a new host from `*.example`).
- **Auto commit+push:** `scripts/dotfiles-sync.sh` does `pull --rebase --autostash`
  → `add -A` → `commit "auto(<host>): …"` → `push`. Skips cleanly when offline.
  Driven by user timer `dotfiles-sync.timer` (unit source in `systemd/`, deployed to
  `~/.config/systemd/user/`): ~2 min after enable, 3 min after login, then every
  15 min; `Persistent=true` catches up after suspend. Run by hand:
  `systemctl --user start dotfiles-sync.service`. No sudo (user systemd).
- **New machine:** `./install.sh` handles it (stow → apply-host-local.sh → enable
  timer). Existing machine, manual: `cp systemd/dotfiles-sync.* ~/.config/systemd/user/
  && systemctl --user daemon-reload && systemctl --user enable --now dotfiles-sync.timer`.

## Cross-machine WORK sync (~/code via Syncthing) — both machines

**Goal:** projects (incl. uncommitted WIP) mirror between laptop & desktop, and each
machine can see what the other was last doing. Config sync (above) is separate.

- **Transport:** Syncthing (P2P, no cloud), user service `syncthing.service`,
  sharing `~/code` as folder id `code`. GUI at `http://127.0.0.1:8384`.
- **Convention:** projects live under `~/code` — that whole tree syncs both ways.
- **Awareness:** each host writes ONLY its own heartbeat to
  `~/code/.sync-status/<host>.status` (project / branch / last-touched file /
  timestamps — no write conflicts by design; Syncthing carries the files).
  Writer: `scripts/work-status.sh update`, driven by `work-heartbeat.timer`
  (every 5 min; unit source in `systemd/`, deployed to `~/.config/systemd/user/`).
  Reader: `work-status` (zsh alias → `scripts/work-status.sh`) prints all hosts.
- **New machine:** install.sh does everything except pairing. Manual on an
  existing machine: install syncthing (`--exclude=gdm`!), `mkdir -p ~/code`,
  `systemctl --user enable --now syncthing.service`,
  `syncthing cli config folders add --id code --label code --path ~/code`,
  `cp systemd/work-heartbeat.* ~/.config/systemd/user/ && systemctl --user
  daemon-reload && systemctl --user enable --now work-heartbeat.timer`.
- **One-time device pairing (needs both machines up):** on each GUI
  (127.0.0.1:8384) → Add Remote Device (IDs: `syncthing cli show system | rg myID`),
  accept on the other side, then share folder `code` with the new device and
  accept the folder on the receiving end (point it at `~/code`).
  Laptop `fedora` device ID: `YNY5WM2-XC2PYS3-XKKGQOK-HFCELUE-ASMFA3N-63QIK7N-FG6WTCN-VKZLEAF`.

## Framework Laptop 13 (host `fedora`, Ryzen AI 7 350)

### Bluetooth
- **Packages:** `blueman` (+ deps `nautilus-python`, `blueman-nautilus`). Always
  `dnf … --exclude=gdm` (GDM install once locked the user out).
- **Services:** `bluetooth.service` (system, already enabled). `blueman-applet`
  autostarts via `exec-once = blueman-applet` in `hypr/.config/hypr/local.fedora.conf`
  (laptop-only — the shared `hyprland.conf` stays applet-free so the desktop is
  unaffected). Provides the waybar systray BT menu.
- **Pair headphones (CLI):**
  ```
  bluetoothctl
  > power on          # already on
  > scan on           # note the device MAC, then: scan off
  > pair  <MAC>
  > trust <MAC>       # trust = auto-reconnect forever
  > connect <MAC>
  ```
  Or use the blueman tray icon. AirPods need the case **setup button** held until it
  blinks white to enter pairing mode (they pair by iCloud proximity on Apple devices,
  but a non-Apple host requires that button — no CLI workaround).
- **A2DP vs HSP gotcha:** if audio is tinny/mono, the device is on the HSP/HFP
  headset profile. Switch to stereo:
  `pactl set-card-profile bluez_card.<MAC_underscored> a2dp-sink`
  (or blueman → right-click device → Audio Profile → High Fidelity Playback A2DP).

### Caffeine / idle-inhibit waybar toggle — DONE 2026-07-18 (shared)
Implemented as **shared** config (both machines), not per-host: the `custom/caffeine`
module lives in `waybar/config.jsonc`, its amber-chip CSS in `style.css.base`, and the
toggle in `hypr/.config/hypr/caffeine-toggle.sh` (stow-linked to `~/.config/hypr/`).
The toggle **kills/relaunches `hypridle`** (ON = hypridle killed, so NO idle timers
exist → no blank/lock/suspend; OFF = relaunch via `hyprctl dispatch exec` for a clean
Wayland connection). It signals waybar with `SIGRTMIN+9` after flipping state. The only
per-host bit is putting `"custom/caffeine"` in each host's `modules-right`
(`local.<host>.jsonc`) — both hosts now have it. `hypridle` is installed + autostarted
(`hyprland.conf` exec-once) on both. For the amber styling to render, run
`scripts/switch-theme.sh <theme>` once (regenerates `style.css` from `.base`).

### Power daemon — desktop keeps `tuned-ppd` (2026-07-18)
On `brandon-fedora`, `install-qol.sh`'s `power-profiles-daemon` install silently fails:
Fedora 44 ships **`tuned-ppd`** (active), which owns the same power-profiles D-Bus
service and conflicts with ppd. Left as-is — tuned-ppd is the F44 default and the DE/
waybar widgets talk to the same D-Bus API. Consequence: **no `powerprofilesctl` CLI**
on the desktop (harmless — battery-less). To force ppd instead:
`sudo dnf swap tuned-ppd power-profiles-daemon`. The laptop is likely on tuned-ppd too.

## Laptop vs desktop differences
- **waybar:** laptop `modules-right` includes `battery`; desktop omits it.
- **hypr:** monitor (`eDP-1 2880x1920@120 2x` vs desktop `DP-1`+`HDMI-A-1`); file
  manager bind (`nautilus` vs `dolphin`); laptop has the `blueman-applet` exec-once.
- Per-host files: `local.fedora.*` (laptop) vs `local.brandon-fedora.*` (desktop).
