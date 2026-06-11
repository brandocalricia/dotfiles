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
