# branco/dotfiles

A cross-platform dotfiles system with 21 themes, one-command switching, and full Linux + macOS support.

`Platform: Linux | macOS` &nbsp; `Themes: 21` &nbsp; `Shell: zsh + oh-my-zsh` &nbsp; `WM: Hyprland + Aerospace`

---

**Theme switching:**
```bash
bash ~/dotfiles/scripts/switch-theme.sh <theme>
```

---

## Quick Start

### Linux (Fedora)

```bash
git clone https://github.com/brandocalricia/dotfiles ~/dotfiles
cd ~/dotfiles && bash install.sh
```

### macOS

```bash
git clone https://github.com/brandocalricia/dotfiles ~/dotfiles
cd ~/dotfiles && bash mac-install.sh
```

**After install on Linux:**
1. Log out → pick **Hyprland** (not uwsm) at SDDM
2. Re-authenticate GitHub CLI: `gh auth login`
3. Drop a wallpaper at `~/Pictures/wallpapers/` and update the `swaybg` line in `hyprland.conf`
4. For OBS screen capture: add a **Screen Capture (PipeWire)** source — the portal is pre-wired

---

## Theme Switching

```bash
bash ~/dotfiles/scripts/switch-theme.sh <theme-id>
```

On apply, the script rewrites configs for every themed component and reloads them live — no logout needed.

### Custom Palettes

| Theme ID | Name | Vibe |
|---|---|---|
| `nord` | Nord | Cool Arctic blues and muted grays; calm and precise |
| `summer` | Summer | Warm yellows, sandy tones, and sun-washed pastels |
| `twilight` | Twilight | Deep purples and indigo with golden-hour accents |
| `bonfire` | Bonfire | Burnt oranges, deep reds, and ember glows on dark charcoal |
| `crimson` | Crimson | High-contrast dark base with bold reds and electric accents |
| `ocean` | Ocean | Deep teals, seafoam greens, and midnight navy |

### Community Themes

| Theme ID | Name | Vibe |
|---|---|---|
| `catppuccin` | Catppuccin Mocha | Pastel mauve, lavender, and soft pinks on a deep midnight base |
| `tokyo-night` | Tokyo Night | Neon blues and electric purples inspired by rain-soaked city lights |
| `gruvbox` | Gruvbox Dark Hard | Earthy retro palette: warm ambers, greens, and terracotta on dark brown |
| `dracula` | Dracula | Classic dark: electric purple, pink, and cyan on near-black |
| `rose-pine` | Rosé Pine | Dusty rose, pine green, and foam on deep, muted purple-gray |
| `everforest` | Everforest Dark Hard | Muted greens and warm earth tones; easy on the eyes in any light |
| `kanagawa` | Kanagawa Wave | Japanese ink-painting aesthetic: deep indigo with gold and sakura accents |
| `onedark` | One Dark Pro | Balanced everyday dark theme with cool blues and subtle purple |
| `material` | Material Deep Ocean | Deep near-black with vibrant primary colors and crisp white text |
| `synthwave` | Synthwave '84 | Neon pink and electric cyan on dark purple; 80s retro aesthetic |
| `ayu-dark` | Ayu Dark | Minimal dark blue-black with soft orange and gold accents |
| `moonlight` | Moonlight | Blue-tinted dark with cool purples and teal; a refined night theme |
| `solarized` | Solarized Dark | The classic precision-designed palette with mathematically chosen contrast |
| `horizon` | Horizon Dark | Warm-cool contrast: coral reds and electric blues on dark navy |
| `palenight` | Palenight | Material-inspired deep navy base with purple and cyan highlights |

---

## What Gets Themed

Every component below is updated atomically on each `switch-theme.sh` call.

| Component | What changes |
|---|---|
| **Hyprland borders** | Active window gradient (2-color), inactive border color |
| **Waybar** | Bar background + alpha, workspace pills (active/inactive), module accent colors, clock color |
| **foot terminal** | Background, foreground, full 16-color ANSI palette |
| **Ghostty terminal** | Full palette (macOS; uses generated theme files in `ghostty/themes/`) |
| **mako notifications** | Background color, foreground text, border color |
| **btop** | Full color scheme (generated btop theme file) |
| **fuzzel launcher** | Background, text, selection highlight, border |
| **hyprlock** | Blur overlay tint, input field colors, clock and date colors |
| **fastfetch** | Accent color for system info display |

---

## Stack

| Component | Tool | Platform |
|---|---|---|
| WM | Hyprland 0.55.2 (ashbuk/Hyprland-Fedora COPR) | Linux |
| WM | Aerospace | macOS |
| Bar | Waybar | Linux |
| Terminal | foot | Linux |
| Terminal | Ghostty | macOS |
| Launcher | fuzzel | Linux |
| Notifications | mako | Linux |
| Lock screen | hyprlock | Linux |
| Shell | zsh + oh-my-zsh + Powerlevel10k | Both |
| Theme switcher | `scripts/switch-theme.sh` | Both |

**Hardware this was built on:** Ryzen 7 7800X3D · RX 7800 XT · 32GB RAM · Fedora 44

---

## Keybinds

| Keybind | Action |
|---|---|
| `SUPER + Return` | Open terminal (foot) |
| `SUPER + R` | App launcher (fuzzel) |
| `SUPER + B` | Open Brave |
| `SUPER + E` | File manager |
| `SUPER + Q` | Close window |
| `SUPER + F` | Fullscreen |
| `SUPER + V` | Toggle floating |
| `SUPER + P` | Pseudo-tile |
| `SUPER + J` | Toggle split direction |
| `SUPER + L` | Lock screen (hyprlock) |
| `SUPER + M` | Exit Hyprland (logout) |
| `SUPER + .` | Clipboard history (fuzzel) |
| `SUPER + SHIFT + S` | Screenshot region → clipboard |
| `SUPER + CTRL + S` | Screenshot region → ~/Pictures/ |
| `SUPER + 1-9` | Switch workspace |
| `SUPER + SHIFT + 1-9` | Move window to workspace |
| `SUPER + arrows` | Focus window |
| `SUPER + SHIFT + arrows` | Move window |
| `SUPER + scroll` | Cycle workspaces |
| `SUPER + drag (LMB)` | Move floating window |
| `SUPER + drag (RMB)` | Resize window |

---

## Repo Structure

```
dotfiles/
├── themes/          # 21 theme color palettes (sourced by switch-theme.sh)
├── scripts/         # switch-theme.sh
├── hypr/            # Hyprland WM config + hyprlock lock screen
├── waybar/          # Status bar config and stylesheet
├── foot/            # Linux terminal (foot.ini)
├── ghostty/         # macOS terminal config + generated theme files
├── aerospace/       # macOS tiling WM config
├── mako/            # Notification daemon
├── btop/            # System monitor
├── fuzzel/          # App launcher
├── fastfetch/       # System info display
├── zsh/             # .zshrc + Powerlevel10k prompt config
├── brave/           # Brave browser flags
├── gh/              # GitHub CLI config (re-auth required on each machine)
├── install.sh       # Linux (Fedora) installer
└── mac-install.sh   # macOS installer
```

Each directory is a **GNU stow package**: `stow <name>` creates symlinks from `~/.config/` back into the repo so every config edit is automatically tracked by git.

---

## Day-to-day Workflow

### Editing configs

Everything is symlinked, so edit files at their normal paths:

```bash
nano ~/.config/hypr/hyprland.conf   # edits dotfiles/hypr/.config/hypr/hyprland.conf
hyprctl reload                       # apply without logging out
```

### Saving changes

```bash
cd ~/dotfiles
git add -p                           # review hunks before committing
git commit -m "tweak: description"
git push
```

### Syncing to another machine

```bash
cd ~/dotfiles && git pull
stow hypr waybar foot zsh            # re-stow if new packages were added
```

### Rolling back a broken config

```bash
cd ~/dotfiles
git log --oneline
git checkout <hash> -- hypr/.config/hypr/hyprland.conf
hyprctl reload
```

---

## Known Issues

- **`hyprland-qtutils` missing from COPR** — some rare Qt dialogs won't render. Suppressed via `ecosystem {}` block in `hyprland.conf`.
- **`hypridle`** — crashes without a config. `~/.config/hypr/hypridle.conf` is not included; create one manually to enable auto-lock.
- **Brave keyring prompts** — Brave must launch with `--password-store=basic`. Already handled via `brave-flags.conf` and the `SUPER+B` keybind. Without it, KDE Wallet prompts on every login.
- **OBS screen capture** — use **Screen Capture (PipeWire)**, not the X11 source. `xdg-desktop-portal-hyprland` handles the portal.
- **Wallpaper on fresh install** — `swaybg` won't find anything until you drop an image at `~/Pictures/wallpapers/` and update the `exec-once = swaybg` line in `hyprland.conf`.
- **GitHub CLI auth** — `gh/.config/gh/hosts.yml` stores machine-specific tokens. Run `gh auth login` fresh on each machine.
