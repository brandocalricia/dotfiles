---
description: Write a new vault note from the user's own understanding, wired into the graph
argument-hint: <topic>
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

Create a note on: **$ARGUMENTS**

The point of this vault is notes written from the user's own understanding — not
summaries you generated. So **interview first, write second.**

1. Search the vault for what already exists on this topic. If a note already covers
   it, say so and offer to extend it instead of creating a duplicate.
2. Ask the user to explain the idea in their own words — what it is, where they hit
   it, what it connects to, what still confuses them. Ask follow-ups on the vague
   parts. This is the whole value of the exercise; do not skip it.
3. Write the note in *their* phrasing, keeping their examples and their uncertainty.
   Your job is structure and clarity, not substitution. Where they were unsure, say
   so in the note ("unclear to me: …") rather than smoothing it over.
4. Wire it in:
   - Place it in the right existing folder — do not invent a new one.
   - Link only to notes that **actually exist**; verify each target resolves.
   - Add an inbound link from the relevant `MOC — *.md` hub so it is reachable.
   - Frontmatter: `title`, `created` (today), `tags`.
5. Finish by running `~/dotfiles/scripts/brain-doctor.py --audit --quiet` to confirm
   the score did not drop.

If the user cannot explain it yet, say that plainly and suggest they come back after
working with the idea. An honest gap beats a note they will never trust.
