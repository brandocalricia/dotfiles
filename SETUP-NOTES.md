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

## greetd + SELinux: the xdm_t situation (CURRENT WORKAROUND IN PLACE)

**State**: SELinux enforcing, but `xdm_t` is a customized permissive domain
(`sudo semanage permissive -a xdm_t` — the only customized permissive type).

**Root cause (verified 2026-06-10)**: `/etc/pam.d/greetd` is:

```
auth       sufficient   pam_fprintd.so
auth       include      system-auth
account    include      system-auth
password   include      system-auth
session    include      system-auth
```

No `pam_selinux.so` session lines and no `pam_loginuid.so`, so the user
session never transitions out of greetd's `xdm_t` domain — the entire
Hyprland session runs confined as the display manager.

**Denial inventory while xdm_t was enforcing** (from ausearch, this boot):
foot (ptmx open/ioctl — broken terminals), zsh (.zsh_history.LOCK,
zcompdump map), git (index map), sudo (ptmx), claude (settings.json
write/watch), fc-list/fc-match (font cache map), man (mandb cache), Chrome
(udp name_bind, /proc/pressure), Steam/Proton (pressure-vessel remounts,
/dev/ntsync, execmod on dlls). Brave crash-looped (SIGSEGV/SIGTRAP) under
enforcement; clean ever since permissive.

### Proper fix plan — FUTURE SESSION ONLY, USER AWAKE, RECOVERY TTY OPEN

Goal: session transitions to `unconfined_t` at login; then remove the
permissive workaround. This is a PAM **session-stack** edit (sudo required).

Preparation (before touching anything):
1. Open a root-capable TTY (**Ctrl+Alt+F3**, log in) and KEEP IT OPEN.
2. `sudo cp /etc/pam.d/greetd /etc/pam.d/greetd.bak`
3. Confirm current confinement: `id -Z` in the session → expect `...xdm_t...`.

Edit `/etc/pam.d/greetd` session stack, mirroring `/etc/pam.d/login`
(verified on this host) — final file:

```
auth       sufficient   pam_fprintd.so
auth       include      system-auth
account    include      system-auth
password   include      system-auth
session    required     pam_selinux.so close
session    required     pam_loginuid.so
session    required     pam_selinux.so open
session    include      system-auth
```

(`close` first, `open` immediately before the user-context session modules,
exactly as the comments in `/etc/pam.d/login` prescribe.)

Then:
4. Log out, log back in via tuigreet (or reboot).
5. Verify: `id -Z` → `unconfined_u:unconfined_r:unconfined_t:...`;
   `ps -eZ | grep Hyprland` shows unconfined_t.
6. Run the smoke tests: open foot, run git in a repo, fc-list, launch Brave,
   start Steam — i.e., everything from the denial inventory above.
7. Only after a full healthy reboot cycle: remove the workaround:
   `sudo semanage permissive -d xdm_t`.
8. Repeat the smoke tests. Any new denial: `sudo ausearch -m avc -ts recent`.

Rollback at any point:
- Login broken after the edit → from the open TTY:
  `sudo cp /etc/pam.d/greetd.bak /etc/pam.d/greetd && sudo systemctl restart greetd`
- Breakage after removing permissive → `sudo semanage permissive -a xdm_t`
  restores tonight's working state.
- Absolute worst case (greetd loop, can't log in): from TTY
  `sudo systemctl stop greetd`, then start Hyprland manually from the TTY to
  recover; restore the backup; `sudo systemctl start greetd`.
- NEVER touch display-manager.service, never install/enable another DM.

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

## Theme system gotchas (switch-theme.sh)

`scripts/switch-theme.sh` **fully regenerates** waybar `style.css`,
`foot.ini`, `hyprlock.conf`, `fuzzel.ini`, mako `config`, and the ghostty
theme file from inline templates. Any fix to those files MUST also be made
in the script's template or the next theme switch reverts it. Applied to the
templates tonight: waybar `#battery` CSS, foot select-all removal, hyprlock
NF-ExtraBold family + fingerprint block, fuzzel `terminal=`.
`config.jsonc` (waybar modules/icons) is NOT regenerated — safe to edit.

As of tonight fuzzel/mako/ghostty are stowed like everything else, so the
script writes through symlinks into the repo — keep it that way.

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
