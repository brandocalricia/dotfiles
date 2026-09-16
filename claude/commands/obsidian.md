---
description: "Search the user's Obsidian vault. Use only when they ask you to look at their notes."
argument-hint: <question>
allowed-tools: Bash, Read, Grep, Glob
---

Answer this question **from the user's own vault**, not from general knowledge:

**$ARGUMENTS**

Vault root: `~/Documents/Brain`. Call it Obsidian.

Procedure:

0. If the `brain_search` tool exists, call it first with the user's prompt verbatim
   and treat its "From your vault" block as the primary source. Then continue.
1. Search widely — `grep -ril` across the vault for the key terms.
2. Read the notes that actually matter. Prefer depth over breadth.
3. Cite every claim with the note path as `` `path/to/Note.md` ``.
4. Mark which parts came from their notes and which are yours.

Do not create or edit notes in this command; it is read-only. Write only if they asked.
