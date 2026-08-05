---
description: Report Obsidian vault health and what to do about it
allowed-tools: Bash, Read
---

Run the vault audit and interpret it. Do not change any files.

!`~/dotfiles/scripts/brain-doctor.py --audit`

Then read `~/Documents/Brain/Claude/Health.md` for the detail.

Report back, briefly:

- The score and how it moved (the report's previous value, if the file shows one).
- The two or three problems actually dragging the score down — with the specific
  notes involved, not just counts.
- The top of the **write queue**: concepts the user linked to repeatedly but never
  wrote. These are the highest-leverage notes to author, because the links already
  point there. Name the top three and say what each would need to cover.
- Whether anything needs `/brain-fix` (which rewrites note bodies) versus the weekly
  timer handling it on its own.

Keep it under ~15 lines. This runs often; it should read like a status line, not a report.
