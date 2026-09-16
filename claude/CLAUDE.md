# Global context

## Machines

Always identify this host with `hostname -s`. Never guess from shared notes.

- `fedora` — Framework 13 laptop (Fedora 44 + Hyprland). School daily driver.
- `brandon-fedora` — desktop (Fedora 44 + Hyprland). Stays home.
- `Brandons-MacBook-Air-2` — Mac school laptop. Sibling machine, not a third Fedora host.

Laptop restic bucket is `brandon-fedora-home` (host `fedora`). Desktop bucket is `brandon-desktop-home` (host `brandon-fedora`). Mac: no restic, no B2.

## BrandoObsid is a manual notebook

`~/Documents/BrandoObsid` is the user's BrandoObsid vault (Dropbox folder `BrandoObsid`). Call it BrandoObsid, not "the brain" and not "Obsidian" (Obsidian is the app). They take notes there themselves.

- Do **not** write, create, edit, index, log, roll up, capture, or "keep INDEX current" in the vault unless they explicitly ask (example: "format the notes I just took").
- Do **not** search the vault, call `BrandoObsid_search`, or read notes unless they ask you to look at their notes / vault / BrandoObsid.
- If they do ask, read `~/Documents/BrandoObsid`, cite paths, and stop. Do not add follow-up notes they did not request.

Grok/Claude session logs belong in the tool's own storage, not in BrandoObsid.

## Hard nos (Fedora)

- Never run `~/dotfiles/install.sh`.
- Never `sudo dnf upgrade`; if dnf is required, `--exclude=gdm`. Never touch the display manager / greetd / PAM / GDM.
- Never invent a different WiFi stack. Never print restic secrets or the DU wifi password.
