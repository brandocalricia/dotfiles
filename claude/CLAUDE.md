# Global context

## Knowledge base ("the brain")
The user keeps an Obsidian vault at **`~/Documents/Brain`** (Syncthing-synced
across their laptop `fedora` and desktop `brandon-fedora`, and backed up).

- **At the start of substantive work**, consult **`~/Documents/Brain/Claude/INDEX.md`**
  for current context (active projects, setup, preferences). Read further into
  `Claude/Memory/` or the vault's notes when relevant.
- **At the end of substantive sessions**, append a short summary note to
  **`~/Documents/Brain/Claude/Sessions/<YYYY-MM-DD>.md`** — what was done, key
  decisions, files touched, and any follow-ups. Prefer editing the existing
  day file. (A SessionEnd hook already logs a one-line record automatically;
  your job is the richer human-readable summary when the work merits it.)
- Keep `INDEX.md`'s "Active threads" section current as projects change.

Skip both for trivial/read-only one-off questions — this is for real work.
