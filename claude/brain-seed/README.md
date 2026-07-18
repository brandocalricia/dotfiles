---
tags: [claude, moc]
---
# 🧠 Claude ⇄ Brain

This folder is the bridge between your Obsidian vault and Claude Code. It exists
so Claude always knows your context and every session leaves a durable record.

## How it works
- **`INDEX.md`** — the curated map Claude reads first. Keep the top of it current
  (active projects, machines, preferences). Both machines' Claude sessions are
  told to consult it via the global `~/.claude/CLAUDE.md` pointer.
- **`Sessions/`** — one note per day, auto-appended at the end of *every* Claude
  session by the `claude-session-log.sh` SessionEnd hook (topic, machine, repo,
  transcript path). Claude also writes richer summaries here for substantive work.
- **`Memory/`** — a mirror of Claude's structured memory
  (`~/.claude/.../memory/`), copied in on each session end so it's graphed in
  Obsidian, synced across machines, and backed up. **Read-only mirror** — edit
  the real memory via Claude, not these copies.

## Sync & safety
The whole `Brain` vault is a Syncthing folder (`id: brain`) shared laptop ⇄ PC,
so this knowledge lives on both machines and rides along in the restic backup.

## Query it (Dataview)
Once the Dataview plugin is enabled, e.g. list recent sessions:
````
```dataview
LIST FROM "Claude/Sessions" SORT file.name DESC LIMIT 14
```
````
