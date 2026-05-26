# dotfiles

Brandon's Linux config — Hyprland on Fedora 44.  
Last updated: May 2026. Hardware: Ryzen 7 7800X3D · RX 7800 XT · 32GB RAM.

---

## What's in here

```
dotfiles/
├── hypr/        Hyprland WM + hyprlock (keybinds, gaps, Nord borders)
├── waybar/      Status bar (floating, Nord theme, icon fonts, click handlers)
├── foot/        Terminal emulator (Nord colors, JetBrainsMono, beam cursor)
├── brave/       Brave browser flags (--password-store=basic fixes keyring issues)
├── gh/          GitHub CLI config (you'll need to re-auth: gh auth login)
├── zsh/         Shell config (.zshrc) + Powerlevel10k prompt (.p10k.zsh)
├── install.sh   One-shot setup script for a fresh Fedora machine
└── README.md    You are here
```

Each folder is a **GNU stow package**. Stow creates symlinks from `~/.config/*`
into the repo so edits to your configs are automatically tracked by git.

---

## Fresh machine setup

> Tested on Fedora 44 KDE. Should work on Fedora 43+ with minor adjustments.

```bash
# 1. Clone the repo
git clone https://github.com/brandocalricia/dotfiles ~/dotfiles

# 2. Run the installer
cd ~/dotfiles
bash install.sh
```

The installer handles:
- System update
- RPM Fusion (free + nonfree)
- ashbuk/Hyprland-Fedora COPR
- Brave browser repo
- All packages (hyprland, waybar, foot, fuzzel, mako, hyprlock, hypridle,
  swaybg, cliphist, grim, slurp, wl-clipboard, brightnessctl, playerctl,
  pavucontrol, zsh, git, gh, stow, btop, htop, bat, eza, fd-find, ripgrep,
  fzf, zoxide, fastfetch, obs-studio, ffmpeg, vlc, brave-browser, keepassxc)
- JetBrainsMono Nerd Font (from nerd-fonts releases)
- oh-my-zsh + Powerlevel10k + zsh-autosuggestions + zsh-syntax-highlighting
- GNU stow (links all configs)
- systemd user target for Wayland portals (needed for OBS, screen sharing)
- Flatpaks: Spotify, Obsidian
- kwallet autostart disabled (Brave keyring fix)

**After install:**
1. Log out → pick **Hyprland** (not uwsm) at SDDM login screen
2. Re-authenticate GitHub CLI: `gh auth login`
3. Drop a wallpaper at `~/Pictures/wallpapers/` and update the swaybg line in `hyprland.conf`
4. For OBS screen capture: add a **Screen Capture (PipeWire)** source — the portal is already wired up

---

## Day-to-day workflow

### Editing configs
Since everything is symlinked, just edit normally:
```bash
nano ~/.config/hypr/hyprland.conf   # edits ~/dotfiles/hypr/.config/hypr/hyprland.conf
hyprctl reload                       # apply changes without logging out
```

### Saving changes to the repo
```bash
cd ~/dotfiles
git add .
git commit -m "tweak: describe what you changed"
git push
```

### Pulling updates on another machine
```bash
cd ~/dotfiles && git pull
# Re-stow if you added new packages:
stow hypr waybar foot brave gh zsh
```

### Rolling back a broken config
```bash
cd ~/dotfiles
git log --oneline        # find the commit you want
git checkout <hash> -- hypr/.config/hypr/hyprland.conf
hyprctl reload
```

---

## Keybind reference

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

## Stack details

### Hyprland
- Version: 0.55.2 via ashbuk/Hyprland-Fedora COPR
- Config: `hypr/.config/hypr/hyprland.conf`
- Lock screen config: `hypr/.config/hypr/hyprlock.conf`
- Gaps: 3px inner / 6px outer
- Rounding: 8px
- Active border: Nord blue gradient (`#88c0d0` → `#81a1c1` at 45°)
- Inactive border: Nord dark (`#3b4252`)

### Waybar
- Config: `waybar/.config/waybar/config.jsonc`
- Style: `waybar/.config/waybar/style.css`
- Position: floating top bar with margins
- Left: workspaces
- Center: clock (Mon May 25 09:10 PM)
- Right: network · volume · CPU · memory · disk · tray
- Click handlers: CPU/memory → btop · network → nmtui · volume → pavucontrol

### foot terminal
- Config: `foot/.config/foot/foot.ini`
- Font: JetBrainsMono Nerd Font, size 11
- Background: Nord `#2e3440` at 95% opacity
- Cursor: beam, Nord cyan

### Waybar module colors (Nord palette)
| Module | Color |
|---|---|
| Clock | `#88c0d0` (Nord frost) |
| CPU | `#ebcb8b` (Nord yellow) |
| Memory | `#d08770` (Nord orange) |
| Disk | `#b48ead` (Nord purple) |
| Network | `#a3be8c` (Nord green) |
| Volume | `#8fbcbb` (Nord teal) |

### Nord color reference
```
#2e3440  polar night darkest (background)
#3b4252  polar night dark
#434c5e  polar night mid
#4c566a  polar night light
#d8dee9  snow storm dark (foreground)
#e5e9f0  snow storm mid
#eceff4  snow storm bright
#8fbcbb  frost teal
#88c0d0  frost light blue  ← primary accent
#81a1c1  frost blue
#5e81ac  frost dark blue
#bf616a  aurora red
#d08770  aurora orange
#ebcb8b  aurora yellow
#a3be8c  aurora green
#b48ead  aurora purple
```

---

## Known issues / notes

- `hyprland-qtutils` not available in ashbuk COPR — some rare dialogs won't render. Suppressed via `ecosystem {}` block in hyprland.conf.
- `hypridle` crashes without a config (create `~/.config/hypr/hypridle.conf` to enable auto-lock — not included yet).
- Brave browser must be launched with `--password-store=basic` (already handled via `brave-flags.conf` and the SUPER+B keybind). Without this, KDE Wallet prompts on every login.
- OBS: use **Screen Capture (PipeWire)** source — not the old X11 source. `xdg-desktop-portal-hyprland` handles this.
- On a new machine: wallpaper won't auto-load until you drop an image at `~/Pictures/wallpapers/` and update the `exec-once = swaybg` line in `hyprland.conf`.
- GitHub CLI (`gh`) stores auth tokens in `gh/.config/gh/hosts.yml`. These are machine-specific — run `gh auth login` fresh on each machine.
