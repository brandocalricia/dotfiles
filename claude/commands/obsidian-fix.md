---
description: Repair the Obsidian vault (aliases, frontmatter, dead links, clutter)
allowed-tools: Bash, Read, Edit
---

Repair the vault. Show the user what will change before changing it.

1. Preview first:

!`~/dotfiles/scripts/brain-doctor.py --all --dry-run`

2. Summarise the preview in a few lines. Call out `--unlink` specifically — it
   rewrites note bodies, converting fabricated `[[links]]` to plain text. The text
   survives; only the brackets go.
3. If anything looks destructive or surprising, stop and ask. Otherwise run
   `~/dotfiles/scripts/brain-doctor.py --all` and report the new score.

The vault is not a git repo, so there is no undo beyond backups. Before the first
`--unlink` of a session, make one:
`tar czf ~/obsidian-backup-$(date +%F).tar.gz -C ~/Documents Brain`

Fixes the tool cannot make on its own — handle these yourself if the report lists them:

- **Duplicate titles**: read both notes. Merge into whichever has more substance and
  better placement, repoint links, delete the loser. Do not merge blindly — check
  whether they are genuinely the same topic first.
- **Isolated notes**: no links in or out, so retrieval never reaches them. Read each,
  then add two or three links to genuinely related existing notes. Never invent a
  link target — if nothing fits, the note may belong in `04-Archive/`.
