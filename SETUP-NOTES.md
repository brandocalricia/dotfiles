# SETUP-NOTES — Framework Laptop 13 (Fedora 44, Hyprland via ashbuk COPR)

Machine-specific quirks and the documented fix-plans from the 2026-06-10
diagnostics/restoration session. The desktop is the other consumer of this
repo; anything marked per-machine lives in untracked files.

## Hardware quirks

- **Panel**: BOE NE135A1M-NY1, **2880x1920@120Hz, 3:2** (not 2880x1800 as
  casually remembered). Pinned explicitly in `local.conf`; without that line
  Hyprland's auto-defaults happen to pick the right mode and 2x scale.
- **Power supplies**: `/sys/class/power_supply/` contains `ACAD` (adapter),
  `BAT1` (battery), **and four `ucsi-source-psy-USBC000:00x` USB-C source
  entries**. The waybar battery module MUST pin `"bat": "BAT1"` and
  `"adapter": "ACAD"` or it can latch onto a UCSI device.
- Fingerprint reader present and enrolled (used by hyprlock + PAM).

## Internal microphone (Krackan Point) — FIXED 2026-06-13

**Symptom**: built-in mic produced silence/popping; webcam fine. Default
capture kept landing on an empty headset jack or a dead "Digital Microphone".

**Two separate firmware bugs on this board** (don't conflate them):
1. **Phantom ACP**: the BIOS ACPI tables falsely declare an AMD ACP that
   isn't wired to anything → kernel makes card 2 `acp-pdm-mach`, surfaced as
   "Digital Microphone". Zero mixer controls, only popping. A ghost — it will
   never carry audio. (Framework SoftwareFirmwareIssueTracker#166.)
2. **The real internal mic is on the Realtek ALC285 HDA codec** (card 1, pin
   node 0x12 `[Fixed] Mic at Int`). It works — proven by direct ALSA capture
   (`arecord -D hw:1,0` after `amixer -c 1 set 'Internal Mic' cap`). The
   breakage was **UCM**: WirePlumber's UCM profile exposed only `HiFi__Headset`
   / `HiFi__Mic1` and never flipped the internal-mic capture switch on, so the
   ADC stayed locked to the empty jack.

**The fix — disable ALSA UCM for this card in WirePlumber** (NOT a kernel
module, NOT modprobe, NOT initramfs, NOT a hardware failure — the user's first
hypothesis, all ruled out by the codec dump + direct-ALSA test). With UCM off,
ACP falls back to the plain `analog-stereo` profile whose `Internal Microphone`
port (priority 8900) is auto-selected. Verified key against WirePlumber 0.5
docs AND the shipped `alsa.lua`: `monitor.alsa.properties` does NOT forward
`use-ucm` to devices — must use a **device rule** (`monitor.alsa.rules`, applied
to device props at `prepareDevice`).

**System file (untracked — recreate if lost)**:
`/etc/wireplumber/wireplumber.conf.d/fw13-mic.conf`
```
monitor.alsa.rules = [
  {
    matches = [
      { device.name = "alsa_card.pci-0000_c1_00.6" }
    ]
    actions = {
      update-props = {
        api.alsa.use-ucm = false
      }
    }
  }
]
```
Apply: `systemctl --user restart wireplumber` (no reboot). Confirm with
`pw-dump | grep use-ucm` (device shows `api.alsa.use-ucm = False`) and
`pactl list sources short` (want `...analog-stereo`, not `HiFi__*`).

**Rollback**: `sudo rm /etc/wireplumber/wireplumber.conf.d/fw13-mic.conf` then
`systemctl --user restart wireplumber`. Single artifact, fully reversible.

**Tradeoff**: UCM off = generic ALSA jack-detection switching instead of UCM
"HiFi" profiles. Verified after: speakers + internal mic work; headset-jack mic
is the other analog port (`analog-input-headset-mic`, activates on plug-in,
untested for lack of a headset). If output switching ever misbehaves, scope the
rule tighter or revisit. Survived a relogin; should survive reboot (drop-in is
read at WirePlumber start). **Real upstream fix** is a Framework BIOS update to
the audio verb table — if one lands, this drop-in can be removed and retested.

## Per-machine local.conf (untracked — recreate from this if lost)

```ini
# Framework Laptop 13: BOE NE135A1M-NY1 panel, 2880x1920@120 (3:2), 2x scale
monitor = eDP-1, 2880x1920@120, 0x0, 2
# NOTE: $mod is defined after this file is sourced — use SUPER literally here
bind = SUPER, E, exec, nautilus
exec-once = swaybg -i ~/Pictures/wallpapers/1994882-final.jpg -m fill
```

The shared `hyprland.conf` no longer binds a file manager — each host adds
its own in `local.conf` (desktop: dolphin). Remember: **`$mod` is not yet
defined when local.conf is sourced** (sourced at the autostart section,
`$mod = SUPER` comes later) — use `SUPER` literally in local.conf binds.

## greetd + SELinux: xdm_t session confinement (FIXED 2026-06-11)

**State**: SELinux fully enforcing, NO customized permissive domains. The
session transitions to `unconfined_t` at login via pam_selinux lines in
`/etc/pam.d/greetd`. Verified after a cold boot: `id -Z` →
`unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023`;
`ausearch -m avc -ts boot` → `<no matches>`.

**History**: greetd's PAM file had no `pam_selinux.so`/`pam_loginuid.so`
session lines, so the entire Hyprland session ran confined as greetd's
`xdm_t` domain. Worked around 2026-06-10 with `semanage permissive -a xdm_t`;
properly fixed 2026-06-11 (session stack edit below) and the workaround
removed (`semanage permissive -d xdm_t`).

**The fix** — `/etc/pam.d/greetd` session stack mirrors `/etc/pam.d/login`.
Current file (single-space separators — typed by hand at the TTY; PAM
tokenizes on whitespace, alignment is cosmetic):

```
auth sufficient pam_fprintd.so
auth include system-auth
account include system-auth
password include system-auth
session required pam_selinux.so close
session required pam_loginuid.so
session required pam_selinux.so open
session include system-auth
```

(`close` first session rule, `open` immediately before the user-context
session modules, per the comments in `/etc/pam.d/login`.)

**Durability across updates (verified)**: the file is owned by the greetd
RPM as `%config(noreplace)` (fileflags 17) — package updates keep the local
file and drop the packaged version as `.rpmnew`. After greetd upgrades,
check for `/etc/pam.d/greetd.rpmnew` and confirm `id -Z` is still
unconfined after relogin.

**Pre-fix backups** (the old 183-byte file without the session lines):
`/root/pam-greetd-backup-1781204878/greetd` and `/etc/pam.d/greetd.bak`.

**Smoke-tested 2026-06-11 under full enforcement** (fresh boot): fingerprint
login at tuigreet, waybar battery (BAT1), foot (PTY), Super+R fuzzel,
notify-send styled mako, btop via fuzzel→foot, zsh history persistence,
`git status` in ~/dotfiles, Brave stable (no crash-loop), hyprlock
fingerprint-alone AND password-alone unlock, `fc-list`, Steam to library
screen. All passed; zero AVC denials.

**Rollback if this ever regresses** (e.g. session lands back in xdm_t):
- First check `/etc/pam.d/greetd` still has the three session lines.
- Broken login after any PAM change → from a root TTY:
  `cp /etc/pam.d/greetd.bak /etc/pam.d/greetd && systemctl restart greetd`
  (note: the .bak is the PRE-fix file — restores login but also restores
  xdm_t confinement; re-apply the session lines after).
- Emergency re-add of the old workaround: `sudo semanage permissive -a xdm_t`.
- Absolute worst case (greetd loop, can't log in): from TTY
  `sudo systemctl stop greetd`, start Hyprland manually from the TTY to
  recover, restore the backup, `sudo systemctl start greetd`.
- NEVER touch display-manager.service, never install/enable another DM.

**Historic denial inventory under xdm_t enforcement** (for recognition if it
regresses): foot (ptmx open/ioctl — broken terminals), zsh
(.zsh_history.LOCK, zcompdump map), git (index map), sudo (ptmx), claude
(settings.json write/watch), fc-list/fc-match (font cache map), man (mandb
cache), Chrome (udp name_bind, /proc/pressure), Steam/Proton
(pressure-vessel remounts, /dev/ntsync, execmod on dlls), Brave crash-loop
(SIGSEGV/SIGTRAP).

## hyprlock + fingerprint

**Fixed 2026-06-10** (commit c843ed1): `auth { fingerprint { enabled = true } }`
in hyprlock.conf enables hyprlock's native parallel fingerprint transaction —
fingerprint alone and password alone both unlock (tested).

Background: the PAM chain `hyprlock → login → system-auth` has
`pam_fprintd sufficient` before `pam_unix sufficient`. The stack is either/or
on paper, but a PAM conversation is serial, so fprintd held the prompt and
forced fingerprint-then-password before the native support was enabled.

PAM-side alternative (only if the native fix ever regresses, e.g. after an
authselect change): replace `/etc/pam.d/hyprlock`'s `auth include login` with
a stack that omits pam_fprintd (e.g. `auth sufficient pam_unix.so` +
`auth required pam_deny.so`), keeping native fingerprint for the sensor path.
Rollback: restore the single line `auth include login`.

Caveat to recheck after authselect/profile updates: the main PAM stack still
contains pam_fprintd; today hyprlock's parallel claim wins and the password
path falls through cleanly (tested), but this interaction is not contractual.

## Session environment (greetd launches Hyprland bare)

- `PATH=/usr/local/bin:/usr/bin` — **no `~/.local/bin`** for Hyprland binds
  and exec-once. Anything bound must be in /usr/bin or use an absolute path.
- `$TERMINAL` unset → fuzzel's default terminal command (`$TERMINAL -e`)
  silently failed for Terminal=true apps. Fixed with `terminal=foot {cmd}`
  in fuzzel.ini (commit ef5f792).
- `XDG_SESSION_TYPE=tty` on the Hyprland process itself (inherited from
  greetd); clients correctly get `wayland` + `XDG_CURRENT_DESKTOP=Hyprland`.

## Workflow pack (2026-06-12)

Seven-feature upgrade: waybar workspace glyphs, pyprland scratchpads,
cliphist binds, satty screenshot pipeline, window rules (v3), smart gaps,
DU fastfetch logo. Commits 339f679..a600bdc + docs.

### New packages: pyprland + satty via solopasha COPR (RESTRICTED)

`pyprland` and `satty` are not in Fedora 44 repos. Installed from the
**solopasha/hyprland** COPR, which also ships hyprland 0.51.x and ~60
other packages that must NEVER shadow the ashbuk stack. The repo file
(`/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:solopasha:hyprland.repo`)
therefore carries:

```
includepkgs=pyprland,satty
```

Verified post-install: `dnf repoquery --repo=<solopasha-id>` lists only
pyprland/satty; `dnf check-upgrade` offers nothing from it. **If that
line ever disappears (repo file regenerated by `dnf copr` commands),
re-add it before any dnf upgrade.** Removal path:
`dnf remove pyprland satty && dnf copr disable solopasha/hyprland`.

### Pyprland

- Daemon: `exec-once = /usr/bin/pypr` (absolute path — session PATH).
- Config: `hypr/.config/hypr/pyprland.toml` — pyprland 2.4.7 reads
  `~/.config/hypr/pyprland.toml`, NOT the `~/.config/pypr/config.toml`
  path current upstream docs describe. If a future version stops seeing
  the config, that path migration is the first suspect.
- Binds use `/usr/bin/pypr-client` (fast socket client shipped in rpm).
- Third scratchpad slot is a commented template in pyprland.toml.

### Screenshots

- `~/Pictures/screenshots/` (created by scripts/screenshot.sh on demand).
- satty Enter-key = copy + save + exit (`--actions-on-enter` x3).

### Hyprland windowrule v3 (0.55.x)

Rules are `windowrule = <effect> <value>, match:<prop> <value>`.
The old `windowrule = float class:^(x)$` form parses WITHOUT ERROR but
matches nothing (the class glob is swallowed as the effect's value) —
this bit us: pavucontrol/nm-connection-editor float rules were silently
dead until rewritten. `hyprctl configerrors` will NOT catch this case.

### Waybar workspace glyphs

`hyprland/workspaces` uses `{windows}` + `window-rewrite` (config.jsonc,
not theme-templated). Glyphs must exist in JetBrainsMono Nerd Font —
verify with `fc-match "JetBrainsMono Nerd Font" --format='%{charset}'`
before adding; an empty/missing glyph value makes waybar HIDE that
window's representation entirely. Workspace button CSS (occupied /
empty / active) lives in the switch-theme.sh waybar template.
Note: glyphs raise waybar's min module height to 40px (config says 36).

## Keybind reference (ALL custom binds)

Per-machine (local.conf, this laptop):
| Bind | Action |
|---|---|
| Super+E | nautilus (floats centered 60% via window rule) |

Core:
| Bind | Action |
|---|---|
| Super+Return | foot |
| Super+Q | close window |
| Super+M | exit Hyprland |
| Super+T | toggle floating (moved from Super+V 2026-06-12) |
| Super+R | fuzzel launcher |
| Super+P | pseudotile |
| Super+F | fullscreen |
| Super+J | toggle split direction |
| Super+L | hyprlock |
| Super+S | special workspace "magic" |
| Super+` | pyprland dropdown terminal |
| Super+Shift+` | pyprland btop panel |
| Super+V | clipboard history (fuzzel picker) |
| Super+Shift+V | wipe clipboard history (confirm) |

Focus / move / workspaces:
| Bind | Action |
|---|---|
| Super+arrows | move focus |
| Super+Shift+arrows | move window |
| Super+1..0 | workspace 1–10 |
| Super+Shift+1..0 | move window to workspace 1–10 |
| Super+scroll | cycle workspaces |
| Super+LMB/RMB drag | move / resize window |

Screenshots:
| Bind | Action |
|---|---|
| Print | full screen → clipboard + ~/Pictures/screenshots + notify |
| Super+Print | region → satty annotate → clipboard + file (Enter=done) |
| Super+Shift+S | region → clipboard only (fast path) |

Apps:
| Bind | Action |
|---|---|
| Super+B | brave |
| Super+Shift+G | steam |
| Super+Shift+M | spotify (flatpak) |
| Super+Shift+B | foot -e btop |

Media/hardware (XF86 keys): volume up/down/mute, play/next/prev,
brightness up/down — see hyprland.conf bindel/bindl block.

Removed 2026-06-12: Super+period (cliphist), Super+Shift+Print,
Super+Ctrl+S (screenshot variants).

## Dynamic wallpaper theming (2026-06-12)

One engine, two palette sources: `switch-theme.sh <named>` works as
always; `switch-theme.sh dynamic` consumes the gitignored
`themes/dynamic.sh` written by `scripts/generate-dynamic-theme.sh <img>`
(matugen 3.1, Fedora official repo, used as a JSON palette oracle via
`--dry-run --json hex -t scheme-vibrant -m dark` — we never use matugen's
own templating). Dark lock: only `.dark` roles are read; WCAG contrast
enforced in the generator (4.5:1 text, 3.0:1 accents) by lightening
foregrounds only; ANSI colors harmonized toward the wallpaper hue capped
at 15°. Worst-case verified: near-white wallpaper → #161306 surfaces.

**Flow**: `Super+Shift+W` → fuzzel picker → `scripts/set-wallpaper.sh`
updates the swaybg `exec-once` line in untracked `local.conf` (appends if
missing), restarts swaybg, and — when current-theme is `dynamic` —
regenerates the palette and re-runs switch-theme. Enter dynamic mode with
`set-wallpaper.sh --dynamic [img]`; leave it with any named switch.

**New switch-theme sections (apply to named themes too)**:
- zsh prompt: writes `~/.config/zsh/prompt-colors.zsh` (p10k truecolor hex
  overrides, sourced from .zshrc after .p10k.zsh). New terminals pick it
  up automatically; existing ones need `exec zsh`.
- GTK: writes `~/.config/gtk-{3.0,4.0}/gtk.css` (libadwaita named colors,
  Gradience mechanism). Needs `gtk-theme=adw-gtk3-dark` +
  `color-scheme=prefer-dark` in gsettings (in system-setup.sh). The old
  `env = GTK_THEME` line was REMOVED from hyprland.conf — do not re-add,
  it overrides gsettings and breaks libadwaita. Limits: a few deep
  libadwaita widgets keep stock colors; GTK apps re-read css on restart.
- greeter staging: `scripts/stage-greeter-theme.sh` maps ACCENT_PRIMARY to
  a named ANSI color by hue (tuigreet accepts ONLY named colors) into
  `~/.cache/dynamic-theme/tuigreet.txt`.
- scratchpad terminals are killed on switch (colors bake at spawn);
  pyprland respawns them on next toggle.

**Greeter apply (the one system file)**: `sudo sh ~/dotfiles/scripts/greeter-apply.sh`
validates the staged string (strict whitelists) and rewrites ONLY the
`--theme '...'` argument in `/etc/greetd/config.toml`. greetd runs the
command via sh(1) (single quotes required) and reads config **only at
daemon startup → theme shows after reboot, not logout**. Backup at
`/etc/greetd/config.toml.pre-theme-backup`; rollback:
`sudo cp /etc/greetd/config.toml.pre-theme-backup /etc/greetd/config.toml`.
NEVER touch the greetd PAM stack (see the 2026-06-11 section above).

**Cursors**: deliberately not dynamic — no sane recolor pipeline exists;
neutral default kept.

### swww animated transitions (swaybg replacement, 2026-06-13)

swww 0.11.2 (solopasha COPR — fence extended to `pyprland,satty,swww`)
replaces swaybg for animated wallpaper changes. `set-wallpaper.sh` uses
`swww img <path> --transition-type grow --transition-fps 60
--transition-duration 1.2`. Daemon: `swww-daemon` (exec-once); the image
is set by a second exec-once with `--transition-type none` (instant on
login). Per-machine `local.conf` holds both lines; set-wallpaper seds the
`swww img` line's path to persist the choice. Verify flags against the
binary — this version HAS `--transition-duration` (some READMEs don't).

**ROLLBACK to swaybg** (if swww misbehaves):
1. `git revert <swww-commit>` (or check out the prior set-wallpaper.sh).
2. In `~/.config/hypr/local.conf`, replace the two swww exec-once lines:
   ```
   exec-once = swww-daemon
   exec-once = sleep 1 && swww img <PATH> --transition-type none
   ```
   with the single swaybg line:
   ```
   exec-once = swaybg -i <PATH> -m fill
   ```
3. Live session: `pkill swww-daemon; swaybg -i <PATH> -m fill & disown`.
swaybg is still installed; nothing about it was removed.

New packages: matugen, adw-gtk3-theme (both Fedora official — the
solopasha includepkgs fence is unchanged).

## Theme output model — generated vs tracked (2026-06-13)

`scripts/switch-theme.sh` writes ONLY gitignored paths. The repo tree stays
clean in every theme/dynamic mode, and a stray `git add -A` can't overwrite
blackgold's committed state. Three tiers:

1. **Gitignored live + tracked `<file>.base` seed** (the `local.conf` idiom).
   The full-overwrite outputs + fastfetch: `waybar/style.css`, `foot/foot.ini`,
   `hypr/hyprlock.conf`, `hypr/colors.conf`, `mako/config`, `fuzzel/fuzzel.ini`,
   `fastfetch/config.jsonc`, `ghostty/themes/active`. switch-theme writes the
   live file; `install.sh` seeds it from `.base` on fresh install (so first
   login has valid configs before any switch — e.g. hyprland's
   `source colors.conf` resolves). **Editing structure**: for the `cat>`
   outputs edit the heredoc IN switch-theme.sh, then re-render + refresh the
   `.base` (`switch-theme.sh blackgold` then `cp <live> <live>.base`). For
   **fastfetch** (only sed-patched, not heredoc-generated) edit
   `config.jsonc.base`, then re-seed. `.base` files hold the canonical
   **blackgold** render — keep them in sync if you change blackgold.

2. **Tracked config that references a generated file** (stays hand-editable):
   - `hypr/hyprland.conf` — `source = ~/.config/hypr/colors.conf`; borders use
     `$border_active_1/2` + `$border_inactive` (defined in the generated
     colors.conf). switch-theme NO LONGER sed-patches hyprland.conf.
   - `ghostty/config` — static `theme = active`; switch-theme writes the
     gitignored `themes/active` palette (like btop's `active.theme`). The old
     per-name `ghostty/themes/<name>` files were removed (dead under this model).

3. **Other generated (non-repo or already-ignored)**: btop `active.theme`,
   zsh `~/.config/zsh/prompt-colors.zsh`, GTK `~/.config/gtk-*/gtk.css`,
   `themes/dynamic.sh`, btop `dynamic.theme`, tuigreet staging.

fuzzel/mako/ghostty are stowed (directory-level) like everything else — the
script writes through the symlinks into the repo working tree (now gitignored).
`install.sh` stows them too (was previously missing from the Linux list).
Commits 4ea271d & e60d638.

## Missing vs desktop / app notes

- **dolphin**: not installed here (bind moved per-machine; nautilus on laptop).
- **ghostty**: configs in repo, app not installed on the laptop.
- **Plain "JetBrains Mono"** (non-Nerd) is NOT installed here — only the Nerd
  variants. ghostty config says `font-family = JetBrains Mono`, which on this
  laptop resolves to Noto Sans. **Before changing it: on the desktop run
  `fc-match "JetBrains Mono"`** — if it resolves to a real JetBrainsMono file
  there, the setting is intentional and needs per-machine handling instead;
  if it also falls back, change to `JetBrainsMono Nerd Font` in the repo.
- Valid fontconfig family names here: `JetBrainsMono Nerd Font`,
  `JetBrainsMono NF`, plus `Mono`/`Propo`/`NL` variants and per-weight
  families like `JetBrainsMono NF ExtraBold`. "JetBrainsMono Nerd Font
  ExtraBold" is NOT a family (that bug bit hyprlock's clock).
- **Brave**: launches as a systemd transient scope (likely DBus activation —
  unverified); crash-looped only under xdm_t enforcement, clean since.

## Btrfs snapshot safety net (snapper) — 2026-06-13

System-level rollback for bad dnf transactions / `/etc` mistakes / botched updates.
**Config in git does NOT protect against these — this does.** Set up and end-to-end
*tested* 2026-06-13: a planted `/etc` file was caught by `snapper status` and removed by a
scoped `undochange`, confirmed gone. Born from the 2026-06-10 near-disaster (~8h recovery).

**What's installed/configured (Fedora 44 / DNF5 — verified, no COPR):**
- `snapper` 0.13.0 + `libdnf5-plugin-actions`. The DNF4 `python3-dnf-plugin-snapper` is
  **INERT on dnf5** — do not install it.
- Config `root` on `/` (subvol `root`, id 256). `.snapshots` = nested subvol id 259.
  **No fstab entry for `/.snapshots`** — unnecessary on this flat layout; not worth editing a
  boot-critical file. **`/home` deliberately NOT snapshotted** (see OPEN below).
- Retention (`/etc/snapper/configs/root`): HOURLY 5 / DAILY 7 / WEEKLY 4 / MONTHLY 0 /
  YEARLY 0; NUMBER_LIMIT 20 / IMPORTANT 10; EMPTY_PRE_POST_CLEANUP yes; **qgroups OFF**.
- dnf pre/post hook: `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions` — the
  libdnf5-actions(8) canonical example **plus `-c number`** added to both `snapper create`
  calls. Without that tag the pairs never auto-clean (verified vs snapper(8) "Cleanup
  Algorithms": only snapshots with an algorithm set are ever reaped). Empty `options` field
  ⇒ `raise_error=0` ⇒ a snapshot failure is logged, never aborts the dnf transaction.
- Timers: `snapper-timeline.timer` + `snapper-cleanup.timer` enabled (`boot.timer` left off).
- Layout facts that the recovery steps depend on: fs `/dev/nvme0n1p6`
  UUID `de09bc27-f149-48e9-a1a8-7ca242c24d46`; fstab mounts `subvol=root` **by name**;
  `/boot` is ext4 on a SEPARATE partition → **kernels/initramfs are NOT inside snapshots**.

### Break-glass (a) — dnf/`/etc` broke userspace, system still boots
1. Find the culprit pair: `sudo snapper -c root list` (Description = the dnf command line).
2. Inspect: `sudo snapper -c root status <pre>..<post>`  (detail: `diff <pre>..<post> <file>`).
3a. **Surgical, preferred** — revert only the broken file(s):
    `sudo snapper -c root undochange <pre>..0 /etc/<thing>`
3b. Undo a whole transaction (reverts its files + rpmdb together, coherently):
    `sudo snapper -c root undochange <pre>..<post>`
4. `undochange` is FILE-LEVEL — restart the affected daemons or reboot afterwards.
- **Phase-3 lesson:** a blanket `undochange <pre>..0` ALSO reverts logs / journal / audit /
  package-DB churn. SCOPE to specific files unless you truly mean "undo the whole transaction".

### Break-glass (b) — won't boot at all
Layered, least-risk first. The `rescue` BLS entry runs the SAME root userspace, so it only
helps with kernel/initramfs problems, NOT root-*content* breakage — for that, use a live USB.
- **First try — fix the one file from a Fedora live USB** (lowest risk):
  ```
  mount -o subvol=root /dev/nvme0n1p6 /mnt
  # edit/replace the offending file under /mnt/etc/…   (or chroot to run snapper)
  umount /mnt ; reboot
  ```
- **Full rollback — promote a good snapshot to be `root`** (only if root is deeply broken):
  ```
  mount -o subvolid=5 /dev/nvme0n1p6 /mnt           # top-level (id 5)
  ls /mnt/root/.snapshots/                            # pick a good <N>
  cat /mnt/root/.snapshots/<N>/info.xml              # confirm its date/description
  mv /mnt/root /mnt/root.broken                       # KEEP the broken one
  btrfs subvolume snapshot /mnt/root.broken/.snapshots/<N>/snapshot /mnt/root
  umount /mnt ; reboot                                # fstab mounts subvol=root by name
  ```
  - The new `root` has an EMPTY `.snapshots` (history stays inside `root.broken`) and an empty
    `var/lib/machines` placeholder (subvol 258; systemd recreates it — ignore).
  - **KEEP `root.broken` until the system is verified healthy** (rollback-of-the-rollback).
    Reclaim later by deleting its nested subvols first (`.snapshots/<n>/snapshot`,
    `.snapshots`, `var/lib/machines`) then `btrfs subvolume delete /mnt/root.broken`.
    It shares extents, so leaving it a while costs almost nothing.

### Kernel update broke boot (SEPARATE from snapshots)
`/boot` is ext4 → kernels aren't in snapshots. At the GRUB menu (hold Esc/Shift if hidden)
boot the previous entry `6.19.10-300.fc44` (the `rescue` entry is also there). Snapshot
rollback will NOT fix a bad kernel — this will.

### rpmdb / WAL caveat (Fedora 44 dnf5)
F44's dnf5/PackageKit uses an sqlite rpmdb; a full-root *package-state* rollback can in edge
cases leave the rpmdb inconsistent (the SysGuides `snapper-fedora` project ships a WAL
checkpoint workaround). This does NOT affect `/etc`/file `undochange` (the common case). If
after a whole-transaction revert dnf/rpm misbehave: `sudo rpm --rebuilddb`. Research the WAL
fix before relying on whole-system package-state rollback.

### FUTURE OPTION (NOT installed — needs a separate explicit decision): grub-btrfs
`grub-btrfs` adds a GRUB submenu to boot any snapshot directly — would turn (b) into a menu
pick. Tradeoff: it **regenerates grub.cfg / hooks the bootloader**, the single highest brick
risk on this machine, and because `/boot` is ext4 it also needs an initramfs snapshot-boot
helper to actually land in a snapshot. Deferred on purpose — do NOT install without a written
rollback and a separate approval gate. (This machine has already been to the brink once.)

### RESOLVED (2026-06-13) — off-device encrypted backup of /home (restic → Backblaze B2)
Snapshots cover the SYSTEM only and are same-disk (no help against disk failure, theft, or
full-disk encryption loss). `/home` now has a real off-device, **encrypted** backup via
**restic 0.18.1** (Fedora repo) to a private **Backblaze B2** bucket. Restore-tested
end-to-end (single file pulled back from B2, byte-identical sha256).

**Repository**
- `RESTIC_REPOSITORY=s3:s3.us-west-004.backblazeb2.com/brandon-fedora-home`
- B2's **S3-compatible** endpoint (restic docs recommend it over the native `b2:` backend).
- First backup: 1.56 GiB logical → **782 MiB stored** (compressed 1.76×). Incrementals ~20 MiB.

**Where the secrets live (NONE in git / ~/dotfiles)** — all root-owned `0600` under `/etc/restic`:
- `/etc/restic/home-repo.pass` — restic passphrase (one line). **Also in Bitwarden** ("restic
  /home backup" note). LOSS = permanent, unrecoverable loss of every backup.
- `/etc/restic/b2-home.env` — `RESTIC_REPOSITORY` + `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
  (the B2 keyID/applicationKey) + `RESTIC_PASSWORD_FILE`. B2 key also in Bitwarden.
- `dotfiles/.gitignore` also blocks `*.pass *.env *secret* *.key` as a backstop.

**What runs it** (source of truth = dotfiles; INSTALLED copies do the work):
- `scripts/backup-home.sh` → installed to **`/usr/local/sbin/restic-backup-home.sh`**
- `scripts/restic-home-excludes.txt` → installed to **`/etc/restic/restic-home-excludes.txt`**
- `systemd/restic-backup-home.{service,timer}` → `/etc/systemd/system/`
- Timer: `OnCalendar=daily`, `RandomizedDelaySec=30min`, **`Persistent=true`** (a missed run —
  laptop asleep/off — fires shortly after next boot). System (not user) service: needs root to
  read `/etc/restic` + all of `/home`. Reinstall after editing: see the three `install -m` lines
  in the script header, then `restorecon` + `systemctl daemon-reload`.

**Laptop quirks that bit us (don't re-discover these):**
- **SELinux**: a system service (`init_t`) **cannot exec/read a `user_home_t` file** → the script
  and exclude file MUST live in system paths (`/usr/local/sbin`, `/etc/restic`), not `/home`.
  Running from `/home` fails `status=203/EXEC`. `restorecon` the installed script (→ `bin_t`).
- **No `$HOME` under systemd** → restic runs cacheless (slow, extra B2 calls). Script exports
  `RESTIC_CACHE_DIR=/var/cache/restic`.
- **Stale locks**: an interrupted run (laptop sleeps mid-backup) leaves a repo lock. Script runs
  `restic unlock` at startup — safe because its `flock` guarantees it's the only writer, so any
  lingering lock is from a dead process.

**Exclude philosophy** (`/etc/restic/restic-home-excludes.txt`): back up the irreplaceable, skip
the regenerable. Excluded: `.cache`, **Steam (6.5G, re-downloadable)**, `.rustup/toolchains`,
browser caches, `node_modules`/lang caches, Trash, container image stores. **`.git` is KEPT** —
unpushed commits/branches/stashes are exactly the local-only data at risk. Anything not excluded
is backed up (incl. `~/.ssh`, `~/.gnupg` the moment they exist — neither is present yet).

**Retention** (`forget --prune` each run): `--keep-last 3 --keep-daily 7 --keep-weekly 4
--keep-monthly 12`. (Note: restic only prunes when a snapshot is actually forgotten.)

**EMERGENCY single-file restore** (on this machine, keys still present):
```
set -a; sudo -E bash -c '. /etc/restic/b2-home.env; export RESTIC_CACHE_DIR=/var/cache/restic; \
  restic restore latest --target /tmp/restore --include /home/brandonrobertniehaus/PATH'
# restored copy lands at /tmp/restore/home/brandonrobertniehaus/PATH
```

**FULL DISASTER RESTORE to a brand-new machine** (laptop lost/stolen/dead — assume NOTHING local
survives, `/etc/restic` is gone):
```
# 1. install restic (any Fedora; public repo)
sudo dnf install restic --exclude=gdm
# 2. from BITWARDEN note "restic /home backup" (master password is in your head, not the laptop):
export AWS_ACCESS_KEY_ID=<B2 keyID>
export AWS_SECRET_ACCESS_KEY=<B2 applicationKey>
export RESTIC_REPOSITORY=s3:s3.us-west-004.backblazeb2.com/brandon-fedora-home
export RESTIC_PASSWORD=<restic passphrase>
# 3. verify, then restore
restic snapshots
restic restore latest --target /mnt/newhome      # then move contents into the new /home
```
**Circular-dependency check (passes):** everything needed lives OFF the laptop — restic (public
Fedora repo) + all creds & passphrase (Bitwarden cloud, gated only by the master password in your
head). The `/etc/restic` files die with the laptop, which is exactly why both secrets are mirrored
in Bitwarden. ⚠️ This doc lives in `~/dotfiles` (on the dead laptop) and on GitHub (may need the
lost SSH key) — so the **5 export+restore lines above are also stored in the Bitwarden note**. No
recovery step depends on anything that only existed on the laptop.

## laptop-doctor (scripts/laptop-doctor.sh) — 2026-06-13

One-shot system health check. Run `bash ~/dotfiles/scripts/laptop-doctor.sh`, or fuzzel →
**Laptop Doctor** (launches in foot, holds open with a keypress). Themed via the active theme
(`~/.config/current-theme` → `themes/<name>.sh`, sourced best-effort with a plain fallback —
the diagnostic never breaks if theming is missing). Needs sudo once (fingerprint) for the
SELinux / btrfs / snapshot / `/etc` checks. Checks: failed systemd units (system + user),
SELinux denials this boot, disk + snapshot space, btrfs device-stats + scrub, BAT1 health
(`charge_full` vs `charge_full_design` — this Framework board exposes **µAh `charge_*`**, not
`energy_*`), pending `/etc` `.rpmnew/.rpmsave` (escalates greetd PAM to CRITICAL), pending dnf
updates.

Launcher `applications/laptop-doctor.desktop` (tracked) is symlinked into
`~/.local/share/applications/`; `install.sh` deliberately left unmodified. Exec uses ABSOLUTE
paths — the session PATH has no `~/.local/bin` and a `.desktop` Exec does not expand `$HOME`.

### SELinux denial baseline (so the doctor's count isn't alarming)
Known-benign denials seen under full enforcement. The doctor marks AVCs **CRITICAL only if an
`xdm_t` denial appears** (the greetd regression); everything else is a warning pointing here:
- `tlp_t` running `comm="ps"` denied `dac_override` — TLP power polling; cosmetic, known
  Fedora issue, predates the snapshot work, and is the bulk of the count.
- `snapperd_t` denied `{ reload }` on `init_t` (tclass=system) — snapperd nudging systemd to
  reload; denied but harmless (snapper works fully). New with the 2026-06-13 snapper install.
Neither is fixed — a custom policy module is added risk for zero functional gain. If an
`xdm_t` denial ever appears, see the greetd section: login-confinement has regressed.
