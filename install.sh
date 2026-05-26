#!/usr/bin/env bash
# Brandon's dotfiles installer
# Run on a fresh Fedora KDE install:
#   git clone https://github.com/brandocalricia/dotfiles ~/dotfiles
#   cd ~/dotfiles && bash install.sh

set -e
DOTFILES="$HOME/dotfiles"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

# ── 1. System update ────────────────────────────────────────────
info "Updating system..."
sudo dnf upgrade -y --quiet

# ── 2. Enable RPM Fusion ─────────────────────────────────────────
info "Enabling RPM Fusion..."
sudo dnf install -y --quiet \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# ── 3. Enable Hyprland COPR ──────────────────────────────────────
info "Enabling ashbuk/Hyprland-Fedora COPR..."
sudo dnf copr enable -y ashbuk/Hyprland-Fedora

# ── 4. Enable Brave browser repo ─────────────────────────────────
info "Adding Brave browser repo..."
sudo dnf install -y --quiet dnf-plugins-core
sudo dnf config-manager addrepo \
  --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null || true

# ── 5. Install packages ───────────────────────────────────────────
info "Installing packages..."
sudo dnf install -y --quiet \
  `# Hyprland stack` \
  hyprland xdg-desktop-portal-hyprland waybar foot fuzzel mako \
  hyprlock hypridle swaybg cliphist grim slurp wl-clipboard \
  brightnessctl playerctl pavucontrol \
  `# Terminal tools` \
  zsh git gh stow btop htop bat eza fd-find ripgrep fzf \
  zoxide fastfetch unzip tree inxi xxd NetworkManager-tui \
  `# Dev tools` \
  nodejs \
  `# Apps` \
  obs-studio ffmpeg vlc brave-browser keepassxc \
  `# Fonts` \
  fontawesome-6-free-fonts fontawesome-6-brands-fonts

# ── 6. Install JetBrainsMono Nerd Font ───────────────────────────
info "Installing JetBrainsMono Nerd Font..."
mkdir -p ~/.local/share/fonts
cd /tmp
curl -fLo JetBrainsMono.zip \
  https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip -o JetBrainsMono.zip -d ~/.local/share/fonts/JetBrainsMono
fc-cache -f
cd "$DOTFILES"

# ── 7. Install oh-my-zsh ─────────────────────────────────────────
info "Installing oh-my-zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  warn "oh-my-zsh already installed, skipping"
fi

# ── 8. Install Powerlevel10k ──────────────────────────────────────
info "Installing Powerlevel10k..."
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
else
  warn "Powerlevel10k already installed, skipping"
fi

# ── 9. Install zsh plugins ───────────────────────────────────────
info "Installing zsh plugins..."
ZSH_PLUGINS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
[ ! -d "$ZSH_PLUGINS/zsh-autosuggestions" ] && \
  git clone https://github.com/zsh-users/zsh-autosuggestions \
  "$ZSH_PLUGINS/zsh-autosuggestions"
[ ! -d "$ZSH_PLUGINS/zsh-syntax-highlighting" ] && \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
  "$ZSH_PLUGINS/zsh-syntax-highlighting"

# ── 10. Set zsh as default shell ─────────────────────────────────
info "Setting zsh as default shell..."
chsh -s "$(which zsh)" "$USER" 2>/dev/null || warn "Run: chsh -s $(which zsh)"

# ── 11. Stow dotfiles ────────────────────────────────────────────
info "Stowing dotfiles..."
cd "$DOTFILES"
stow hypr waybar foot btop brave gh zsh fastfetch

# ── 12. Set up graphical-session.target for portals ──────────────
info "Setting up systemd user targets for Wayland portals..."
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/hyprland-session.target << 'EOF'
[Unit]
Description=Hyprland session
Documentation=man:systemd.special(7)
BindsTo=graphical-session.target
Wants=graphical-session-pre.target
After=graphical-session-pre.target
EOF
systemctl --user daemon-reload

# ── 13. Install Flatpaks ─────────────────────────────────────────
info "Installing Flatpaks..."
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y flathub com.spotify.Client md.obsidian.Obsidian

# ── 14. Disable kwallet for Brave ────────────────────────────────
info "Disabling kwallet autostart..."
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/kwalletd6.desktop << 'EOF'
[Desktop Entry]
Hidden=true
EOF

# ── 15. Done ─────────────────────────────────────────────────────
echo ""
info "Done! Next steps:"
echo "  1. Log out → pick Hyprland at SDDM"
echo "  2. hyprctl reload (if already in Hyprland)"
echo "  3. Set wallpaper: swaybg -i ~/Pictures/wallpapers/alps.png -m fill &"
echo "  4. gh auth login (re-authenticate GitHub CLI)"
echo ""
warn "Note: Brave repo may need manual setup if the key import failed."
warn "Note: Steam/Docker/OpenRGB not included — install manually if needed."
