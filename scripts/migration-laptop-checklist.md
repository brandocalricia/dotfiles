# Laptop `fedora` — Grok brain installer (paste in order)

Do this on the laptop, not on brandon-fedora. Do **not** cancel Claude until
this box has had a real TUI day.

1. Pull + restow (so `grok()` lands in `.zshrc`):

```bash
cd ~/dotfiles && git pull --ff-only
# .zshrc is a stow symlink into the repo — pull is enough if stow was already run.
# If grok() is missing from `type grok`, restow zsh:
#   stow -d ~/dotfiles -t "$HOME" -R zsh
exec zsh
```

2. Installer (no sudo). Then inspect:

```bash
bash ~/dotfiles/scripts/install-grok-brain.sh
grok inspect
grok mcp doctor brain
echo "$(hostname -s) $(date -Is)" > ~/.cache/brain-hooks/laptop-installer-done
```

3. **Browser:** `grok login` on this machine. (needs a browser)

4. **TUI modal:** open `grok`, run `/import-claude`, confirm with **Ctrl+I**. (agent cannot click this)

5. **TUI:** `/privacy` — coding-data opt-out + confirm `trace_upload` still false after login.

6. One real TUI session (not `grok -p`). Confirm `~/Documents/Brain/Claude/Sessions/<today>.md` has a real goal, not `(session) · 0`.

7. Do **not** cancel Claude from the laptop until brandon-fedora cancel criteria 2–6 are also true.
