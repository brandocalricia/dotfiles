# This machine — never guess

Two hosts, both Fedora 44 + Hyprland:

- `fedora` = **laptop** (Framework 13, Ryzen AI 7 350)
- `brandon-fedora` = **desktop** (battery-less, dual monitor DP-1 + HDMI-A-1)

SessionStart injects a **This machine** block with `hostname -s`. Trust that. If it is missing, run `hostname -s`. Do not skip that because INDEX already listed both machines.

The vault is shared. INDEX, restic paragraphs, and Grok-migration notes were mostly written on the desktop. Never infer you are on `brandon-fedora` from those. Never infer you are on the laptop because the user said "I".

Name trap: laptop restic bucket is `brandon-fedora-home` (host `fedora`). Desktop bucket is `brandon-desktop-home` (host `brandon-fedora`).
