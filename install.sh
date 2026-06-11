#!/usr/bin/env bash
# Brandon's dotfiles installer — cross-platform (Fedora Linux / macOS)
#
# Fedora:  git clone https://github.com/brandocalricia/dotfiles ~/dotfiles
#           cd ~/dotfiles && bash install.sh
# macOS:   same, or use mac-install.sh for a Mac-only standalone

set -e
DOTFILES="$HOME/dotfiles"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
section() { echo -e "\n${BLUE}══${NC} $1 ${BLUE}══${NC}"; }

# ── OS detection ──────────────────────────────────────────────────
OS="$(uname)"
if [[ "$OS" == "Darwin" ]]; then IS_MAC=true; else IS_MAC=false; fi
if [[ "$OS" == "Linux" ]]; then IS_LINUX=true; else IS_LINUX=false; fi

# ── Install tracking ──────────────────────────────────────────────
INSTALLED=()
SKIPPED=()
installed() { INSTALLED+=("$1"); }
skipped()   { SKIPPED+=("$1"); warn "$1 already installed, skipping"; }

# ══════════════════════════════════════════════════════════════════
# LINUX — Fedora package setup
# ══════════════════════════════════════════════════════════════════
if $IS_LINUX; then
  section "Linux: system update"
  info "Updating system..."
  sudo dnf upgrade -y --quiet

  section "Linux: RPM Fusion"
  info "Enabling RPM Fusion..."
  sudo dnf install -y --quiet \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

  section "Linux: Hyprland COPR"
  info "Enabling ashbuk/Hyprland-Fedora COPR..."
  sudo dnf copr enable -y ashbuk/Hyprland-Fedora

  section "Linux: Brave browser repo"
  info "Adding Brave browser repo..."
  sudo dnf install -y --quiet dnf-plugins-core
  sudo dnf config-manager addrepo \
    --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null || true

  section "Linux: dnf packages"
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
  installed "Linux packages (dnf)"
fi

# ══════════════════════════════════════════════════════════════════
# macOS — Homebrew setup
# ══════════════════════════════════════════════════════════════════
if $IS_MAC; then
  section "macOS: Homebrew"
  if ! command -v brew &>/dev/null; then
    info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Evaluate brew shellenv for the rest of this script
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    installed "Homebrew"
  else
    skipped "Homebrew"
  fi

  section "macOS: CLI tools"
  info "Installing CLI tools via Homebrew..."
  brew install stow git gh zsh btop fastfetch ripgrep fd fzf zoxide eza bat
  installed "Homebrew CLI tools"

  section "macOS: GUI apps"
  info "Installing GUI apps via Homebrew Cask..."
  brew install --cask ghostty aerospace brave-browser obsidian spotify
  installed "Homebrew Cask apps"
fi

# ══════════════════════════════════════════════════════════════════
# SHARED — JetBrainsMono Nerd Font
# ══════════════════════════════════════════════════════════════════
section "Fonts"
if $IS_MAC; then
  FONT_DIR="$HOME/Library/Fonts/JetBrainsMono"
else
  FONT_DIR="$HOME/.local/share/fonts/JetBrainsMono"
fi

if [ -z "$(ls -A "$FONT_DIR" 2>/dev/null)" ]; then
  info "Installing JetBrainsMono Nerd Font..."
  mkdir -p "$FONT_DIR"
  cd /tmp
  curl -fLo JetBrainsMono.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
  unzip -o JetBrainsMono.zip -d "$FONT_DIR"
  rm -f JetBrainsMono.zip
  $IS_LINUX && fc-cache -f
  cd "$DOTFILES"
  installed "JetBrainsMono Nerd Font"
else
  skipped "JetBrainsMono Nerd Font"
fi

# ══════════════════════════════════════════════════════════════════
# SHARED — Zsh: oh-my-zsh, Powerlevel10k, plugins
# ══════════════════════════════════════════════════════════════════
section "Zsh"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  info "Installing oh-my-zsh..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  installed "oh-my-zsh"
else
  skipped "oh-my-zsh"
fi

P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  info "Installing Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
  installed "Powerlevel10k"
else
  skipped "Powerlevel10k"
fi

ZSH_PLUGINS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
if [ ! -d "$ZSH_PLUGINS/zsh-autosuggestions" ]; then
  info "Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS/zsh-autosuggestions"
  installed "zsh-autosuggestions"
else
  skipped "zsh-autosuggestions"
fi

if [ ! -d "$ZSH_PLUGINS/zsh-syntax-highlighting" ]; then
  info "Installing zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS/zsh-syntax-highlighting"
  installed "zsh-syntax-highlighting"
else
  skipped "zsh-syntax-highlighting"
fi

info "Setting zsh as default shell..."
chsh -s "$(command -v zsh)" "$USER" 2>/dev/null || warn "Run manually: chsh -s $(command -v zsh)"

# ══════════════════════════════════════════════════════════════════
# SHARED — Stow dotfiles
# ══════════════════════════════════════════════════════════════════
section "Stow dotfiles"
info "Stowing dotfiles..."
cd "$DOTFILES"
if $IS_LINUX; then
  stow hypr waybar foot btop brave gh zsh fastfetch
fi
if $IS_MAC; then
  stow ghostty aerospace hypr waybar foot btop brave gh zsh fastfetch mako fuzzel
fi
installed "dotfiles (stow)"

# local.conf is gitignored (machine-specific). Create from example if missing
# so that hyprland.conf's `source=` line never errors on a fresh install.
if $IS_LINUX; then
  LOCAL_CONF="$HOME/.config/hypr/local.conf"
  if [ ! -f "$LOCAL_CONF" ]; then
    cp "$DOTFILES/hypr/.config/hypr/local.conf.example" "$LOCAL_CONF"
    warn "Created ~/.config/hypr/local.conf from example — edit it for this machine (wallpaper path, monitor layout, etc.)"
  fi
fi

# ══════════════════════════════════════════════════════════════════
# LINUX — systemd, Flatpak, kwallet
# ══════════════════════════════════════════════════════════════════
if $IS_LINUX; then
  section "Linux: systemd session target"
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
  installed "systemd hyprland-session.target"

  section "Linux: Flatpaks"
  info "Installing Flatpaks..."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub com.spotify.Client md.obsidian.Obsidian
  installed "Flatpaks (Spotify, Obsidian)"

  section "Linux: KWallet"
  info "Disabling kwallet autostart..."
  mkdir -p ~/.config/autostart
  cat > ~/.config/autostart/kwalletd6.desktop << 'EOF'
[Desktop Entry]
Hidden=true
EOF
  installed "KWallet autostart disabled"
fi

# ══════════════════════════════════════════════════════════════════
# Post-install summary
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Install complete!                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"

if [ ${#INSTALLED[@]} -gt 0 ]; then
  echo -e "\n${GREEN}Installed:${NC}"
  for item in "${INSTALLED[@]}"; do
    echo "  ✓ $item"
  done
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo -e "\n${YELLOW}Skipped (already present):${NC}"
  for item in "${SKIPPED[@]}"; do
    echo "  − $item"
  done
fi

echo -e "\n${BLUE}Manual steps required:${NC}"
echo "  1. gh auth login"
echo "  2. bash ~/dotfiles/scripts/switch-theme.sh nord"
if $IS_LINUX; then
  echo "  3. Log out → select Hyprland at SDDM login screen"
  echo "  4. Set wallpaper: swaybg -i ~/Pictures/wallpapers/alps.png -m fill &"
  echo ""
  warn "Note: Brave repo may need manual setup if the GPG key import failed."
  warn "Note: Steam/Docker/OpenRGB not included — install manually if needed."
fi
if $IS_MAC; then
  echo "  3. Open System Settings → Privacy & Security → grant Accessibility to Aerospace"
  echo "  4. Run: aerospace reload-config"
fi
echo ""
