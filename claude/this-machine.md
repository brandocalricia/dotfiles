# This machine — never guess

Three machines:

- `fedora` = **laptop** (Framework 13, Ryzen AI 7 350, Fedora 44 + Hyprland) — school
- `brandon-fedora` = **desktop** (battery-less, dual monitor DP-1 + HDMI-A-1, Fedora 44 + Hyprland) — home
- `Brandons-MacBook-Air-2` = **Mac school laptop** (MacBook Air, Apple Silicon, macOS 15.6.1) — school. Added 2026-08-28.

SessionStart injects a **This machine** block with `hostname -s`. Trust that. If it is missing, run `hostname -s`. Do not skip that because INDEX already listed all machines.

The vault is shared via Syncthing. INDEX, restic paragraphs, and Grok-migration notes were mostly written on the desktop. Never infer you are on `brandon-fedora` from those. Never infer you are on the laptop because the user said "I".

Name trap: laptop restic bucket is `brandon-fedora-home` (host `fedora`). Desktop bucket is `brandon-desktop-home` (host `brandon-fedora`). Mac has no restic bucket.
