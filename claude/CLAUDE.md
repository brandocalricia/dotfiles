# Global context

## Knowledge base ("the brain") — automatic
The user keeps an Obsidian vault at **`~/Documents/Brain`** (Syncthing-synced
across laptop `fedora` and desktop `brandon-fedora`, and backed up). It is wired
to run itself — the user should never have to manage it consciously, and should
never have to type a slash command to get value out of it:

- **Loaded for you automatically.** A SessionStart hook injects
  `Brain/Claude/INDEX.md`, recent session history, and the current vault health
  score. You already have the user's current context — use it.
- **Searched for you automatically.** A UserPromptSubmit hook (`brain-retrieve.py`)
  searches the vault on every prompt and injects matching notes under the heading
  *"From your vault"*. When that block appears, those are **the user's own notes** —
  prefer them over general knowledge, cite them by path, and say so plainly if they
  contradict you or are out of date. The hook stays silent when nothing matches,
  so no block simply means the vault has nothing on this; don't announce that.
- **Logged for you automatically.** A SessionEnd hook writes a factual record of
  every session to `Brain/Claude/Sessions/<date>.md`. You do NOT need to log what
  happened.
- **Audited for you automatically.** `brain-doctor.timer` repairs the vault weekly.
  Health detail lives in `Brain/Claude/Health.md`; see [[Vault-Health-Tooling]].

### Your jobs — do these proactively, without being asked
1. **Capture what the user works out.** When they explain something in their own
   words, reach a conclusion, or hit a non-obvious gotcha, write it into the vault
   as it happens — a new note in the right existing folder, or a few lines appended
   to the note that already covers it. Use *their* phrasing and keep their
   uncertainty ("still unclear to me: …"). Link only to notes that actually exist.
   Mention in one short line that you saved it; don't ask permission first.
2. **Keep `Claude/INDEX.md` honest.** When work starts, finishes, or changes status,
   update its "Active threads" section. This is what makes the brain trustworthy.
3. **Add the why to today's session note.** The hook records *what* changed; you
   append the decisions, rationale, and anything future-you would need.
4. **Save durable facts/preferences to memory** as usual.

### What NOT to write
The vault was badly damaged once by bulk AI generation — 10,769 broken links from
notes that were machine-written rather than user-written. So:

- **Never generate notes on topics the user hasn't actually engaged with.** A note
  is a record of *their* thinking. If they didn't say it, worked it out, or decide
  it, it doesn't go in the vault.
- **Never invent `[[links]]` to notes that don't exist.** Check first.
- Prefer extending an existing note over creating a near-duplicate; colliding
  titles silently misroute every link to them.
- If they can't yet explain something, say so and leave it out. An honest gap beats
  a note they'll never trust.

Keep it low-friction: a few lines, not essays. Treat the brain as the source of
truth for "what's going on," keep it current every session, and let them just work.
