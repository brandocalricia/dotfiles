---
description: "Write or format an Obsidian note. Use only when the user explicitly asks you to write or format notes they took."
argument-hint: <topic>
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

The user asked you to write or format notes on: **$ARGUMENTS**

Obsidian is their manual notebook. Only do what they asked.

1. If they pasted or pointed at notes they already took, format those — keep their wording.
2. If they want a new note, use *their* phrasing. Do not invent content they did not give you.
3. Place it in the existing folder they are using (class notes live under `DU Fall Quarter 2026/`). Do not invent a new folder.
4. Link only to notes that actually exist.
5. Do not run vault "doctor" / audit / fix tools unless they asked for that too.
