# Global context

## Machines

Always identify this host with `hostname -s`. Never guess from shared notes.

- `fedora` — Framework 13 laptop (Fedora 44 + Hyprland). School daily driver.
- `brandon-fedora` — desktop (Fedora 44 + Hyprland). Stays home.
- `Brandons-MacBook-Air-2` — Mac school laptop. Sibling machine, not a third Fedora host.

Laptop restic bucket is `brandon-fedora-home` (host `fedora`). Desktop bucket is `brandon-desktop-home` (host `brandon-fedora`). Mac: no restic, no B2.

## Obsidian is a manual notebook

`~/Documents/Brain` is the user's Obsidian vault (Syncthing folder id `brain`). Call it Obsidian, not "the brain". They take notes there themselves.

- Do **not** write, create, edit, index, log, roll up, capture, or "keep INDEX current" in the vault unless they explicitly ask (example: "format the notes I just took").
- Do **not** search the vault, call `brain_search`, or read notes unless they ask you to look at their notes / vault / Obsidian.
- If they do ask, read `~/Documents/Brain`, cite paths, and stop. Do not add follow-up notes they did not request.

Grok/Claude session logs belong in the tool's own storage, not in Obsidian.

## Hard nos (Fedora)

- Never run `~/dotfiles/install.sh`.
- Never `sudo dnf upgrade`; if dnf is required, `--exclude=gdm`. Never touch the display manager / greetd / PAM / GDM.
- Never invent a different WiFi stack. Never print restic secrets or the DU wifi password.
