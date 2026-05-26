# dotfiles

Brandon's Linux config — Hyprland on Fedora.

## Stack
- **WM:** Hyprland 0.55.2 (ashbuk/Hyprland-Fedora COPR)
- **Bar:** Waybar (floating, Nord theme)
- **Terminal:** foot (Nord)
- **Launcher:** fuzzel
- **Notifications:** mako
- **Lock:** hyprlock
- **Wallpaper:** swaybg
- **Theme:** Nord across all components

## Install on a new machine

```bash
sudo dnf install stow
git clone https://github.com/brandocalricia/dotfiles ~/dotfiles
cd ~/dotfiles
stow hypr waybar foot
```

Requires Hyprland + waybar + foot installed separately (Fedora: see ashbuk/Hyprland-Fedora COPR).
