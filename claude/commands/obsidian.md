---
description: "ALWAYS invoke this skill (do not wait for /obsidian) before answering questions about the user's projects, machines, Fedora/Hyprland setup, config, games (Megabonk, BonkScanner, BakkesMod, Balatro, Geometry Dash, Rusty's Retirement), peek, bwllm, dotfiles, Obsidian vault, past decisions, or anything they might have written down. Search their Obsidian vault first. Required, not optional."
argument-hint: <question>
allowed-tools: Bash, Read, Grep, Glob
---

Answer this question **from the user's own vault**, not from general knowledge:

**$ARGUMENTS**

Vault root: `~/Documents/Brain` (on-disk folder name; always *call* it Obsidian). Notes live mainly in `02-Notes/`, `03-Resources/`,
`01-Projects/`; `Claude/` is machine-maintained (skip it as a source unless asked).

Procedure:

0. If the `brain_search` tool exists, call it first with the user's prompt verbatim
   and treat its "From your vault" block as the primary source. Then continue.
1. Search widely before answering — `grep -ril` across the vault for the key terms,
   then follow `[[wikilinks]]` out of the strongest hits one hop. MOC notes
   (`MOC — *.md`) are hubs; they often point at the good material faster than grep.
2. Read the notes that actually matter. Prefer depth over breadth: 3 notes read
   fully beats 15 skimmed.
3. Answer in the user's own framing, and **cite every claim** with the note it came
   from as `` `path/to/Note.md` `` so they can jump to it.
4. Be explicit about provenance. Mark clearly which parts came from their notes and
   which are yours. Never present your own knowledge as something they wrote.
5. If the vault genuinely doesn't cover it, say so in one line, answer from general
   knowledge, and end with the note you'd write to close the gap — title, the folder
   it belongs in, and the two or three existing notes it should link to.

Do not create or edit notes in this command; it is read-only. Use `/obsidian-note` to write.
