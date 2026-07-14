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

### Caffeine / idle-inhibit waybar toggle — TODO (deferred)
Porting the desktop's caffeine module is **pending**: its implementation lives in the
desktop's (previously gitignored) `local.jsonc`, which wasn't in the repo. Once the
desktop runs the sync above, its `local.brandon-fedora.jsonc` will be committed and
the laptop can mirror the exact module + icons into `local.fedora.jsonc`. `hypridle`
is already installed and autostarted (`hyprland.conf` exec-once) — the idle daemon
the toggle drives.

## Laptop vs desktop differences
- **waybar:** laptop `modules-right` includes `battery`; desktop omits it.
- **hypr:** monitor (`eDP-1 2880x1920@120 2x` vs desktop `DP-1`+`HDMI-A-1`); file
  manager bind (`nautilus` vs `dolphin`); laptop has the `blueman-applet` exec-once.
- Per-host files: `local.fedora.*` (laptop) vs `local.brandon-fedora.*` (desktop).
