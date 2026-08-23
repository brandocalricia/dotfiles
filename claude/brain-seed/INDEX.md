---
tags: [claude, index]
updated: seed
---
# INDEX — start here

Curated context for Claude. Keep the top current; details live in linked notes,
the mirrored `Memory/`, and the dotfiles repo docs. (This is a seeded starter —
the real one syncs in from the other machine via Syncthing.)

## Who / setup
- **Brandon Niehaus** — `brandocalricia@gmail.com`. Developer; projects live in `~/code`.
- Two machines, both **Fedora 44 + Hyprland**: laptop `fedora` (Framework 13 AMD),
  desktop `brandon-fedora`. Source of truth = `~/dotfiles` (stow, auto-synced).

## Cross-machine plumbing
- Config: dotfiles auto-sync. Work: Syncthing `~/code`. Brain: Syncthing `~/Documents/Brain`.
- Shell history: `atuin`. Backups: restic→B2 of `/home` + snapper (system).
  Syncthing is replication, not backup. Live vault is `~/Documents/Brain`;
  `~/Brain` is a stale duplicate if it still exists.

## Active threads (edit me as things change)
- (add current projects / goals here)

## Hard preferences / guardrails
- **Never** touch the display manager; `--exclude=gdm` on every dnf call.
- Keep manual sudo commands to one short line.
- `git pull --rebase` before any push in `~/dotfiles`.
- Don't spawn GUI apps to "test" on the live Hyprland session.

## Map
- `Sessions/` — dated activity log · `Memory/` — Claude's memory mirror
- `Inbox.md` — quick captures (`jot`) · `Rollups/` — weekly digests · `Dashboard.md`
