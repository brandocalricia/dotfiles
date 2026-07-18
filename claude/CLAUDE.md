# Global context

## Knowledge base ("the brain") — automatic
The user keeps an Obsidian vault at **`~/Documents/Brain`** (Syncthing-synced
across laptop `fedora` and desktop `brandon-fedora`, and backed up). It is wired
to run itself — the user should never have to manage it consciously:

- **Loaded for you automatically.** A SessionStart hook injects
  `Brain/Claude/INDEX.md` + recent session history into context at the start of
  every session. You already have the user's current context — use it. No need to
  go read the vault unless you want deeper detail (`Brain/Claude/Memory/`, notes).
- **Logged for you automatically.** A SessionEnd hook writes a rich, factual
  record of every session to `Brain/Claude/Sessions/<date>.md` (goal, files
  touched, activity). You do NOT need to log what happened.
- **Your only jobs — do these proactively, without being asked:**
  1. When work starts, finishes, or changes a project's status, **update the
     "Active threads" section of `~/Documents/Brain/Claude/INDEX.md`** so it always
     reflects reality. This is what keeps the brain trustworthy.
  2. For meaningful decisions, rationale, gotchas, or outcomes, **append a short
     narrative note to today's `Brain/Claude/Sessions/<date>.md`** — the hook
     captures *what* changed; you add the *why* and anything future-you needs.
  3. If the user states a durable fact/preference, also save it to memory as usual.

Keep it low-friction: a few lines, not essays. The user is placing trust in this
system — treat the brain as the source of truth for "what's going on," keep it
current every session, and they should be able to just work normally.
