#!/usr/bin/env bash
# Brandon's dotfiles — macOS standalone installer
#
# Usage:
#   git clone https://github.com/brandocalricia/dotfiles ~/dotfiles
#   cd ~/dotfiles && bash mac-install.sh
#
# Safe to run multiple times — every step checks before acting.

set -e
DOTFILES="$HOME/dotfiles"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
section() { echo -e "\n${BLUE}══${NC} $1 ${BLUE}══${NC}"; }

# ── Guard: macOS only ─────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  echo "Error: mac-install.sh is for macOS only. Use install.sh on Linux."
  exit 1
fi

# ── Install tracking ──────────────────────────────────────────────
INSTALLED=()
SKIPPED=()
installed() { INSTALLED+=("$1"); }
skipped()   { SKIPPED+=("$1"); warn "$1 already installed, skipping"; }

# ══════════════════════════════════════════════════════════════════
# 1. Homebrew
# ══════════════════════════════════════════════════════════════════
section "Homebrew"
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Bring brew into PATH for the rest of this session
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
  installed "Homebrew"
else
  skipped "Homebrew"
fi

# ══════════════════════════════════════════════════════════════════
# 2. CLI tools
# ══════════════════════════════════════════════════════════════════
section "CLI tools"
info "Installing CLI tools via Homebrew..."
# brew install is idempotent — skips already-installed formulae
brew install \
  stow \
  git \
  gh \
  zsh \
  btop \
  fastfetch \
  ripgrep \
  fd \
  fzf \
  zoxide \
  eza \
  bat
installed "Homebrew CLI tools"

# ══════════════════════════════════════════════════════════════════
# 3. GUI apps (Cask)
# ══════════════════════════════════════════════════════════════════
section "GUI apps"
info "Installing GUI apps via Homebrew Cask..."
brew install --cask \
  ghostty \
  aerospace \
  brave-browser \
  obsidian \
  spotify
installed "Homebrew Cask apps"

# ══════════════════════════════════════════════════════════════════
# 4. JetBrainsMono Nerd Font
# ══════════════════════════════════════════════════════════════════
section "Fonts"
FONT_DIR="$HOME/Library/Fonts/JetBrainsMono"
if [ -z "$(ls -A "$FONT_DIR" 2>/dev/null)" ]; then
  info "Installing JetBrainsMono Nerd Font..."
  mkdir -p "$FONT_DIR"
  cd /tmp
  curl -fLo JetBrainsMono.zip \
    https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
  unzip -o JetBrainsMono.zip -d "$FONT_DIR"
  rm -f JetBrainsMono.zip
  cd "$DOTFILES"
  installed "JetBrainsMono Nerd Font"
else
  skipped "JetBrainsMono Nerd Font"
fi

# ══════════════════════════════════════════════════════════════════
# 5. oh-my-zsh
# ══════════════════════════════════════════════════════════════════
section "oh-my-zsh"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  info "Installing oh-my-zsh..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  installed "oh-my-zsh"
else
  skipped "oh-my-zsh"
fi

# ══════════════════════════════════════════════════════════════════
# 6. Powerlevel10k
# ══════════════════════════════════════════════════════════════════
section "Powerlevel10k"
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [ ! -d "$P10K_DIR" ]; then
  info "Installing Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
  installed "Powerlevel10k"
else
  skipped "Powerlevel10k"
fi

# ══════════════════════════════════════════════════════════════════
# 7. Zsh plugins
# ══════════════════════════════════════════════════════════════════
section "Zsh plugins"
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

# ══════════════════════════════════════════════════════════════════
# 8. Default shell
# ══════════════════════════════════════════════════════════════════
section "Default shell"
ZSH_PATH="$(command -v zsh)"
if [[ "$SHELL" != "$ZSH_PATH" ]]; then
  info "Setting zsh as default shell..."
  # Add brew zsh to /etc/shells if not already there
  if ! grep -qx "$ZSH_PATH" /etc/shells; then
    echo "$ZSH_PATH" | sudo tee -a /etc/shells
  fi
  chsh -s "$ZSH_PATH" "$USER" 2>/dev/null || warn "Run manually: chsh -s $ZSH_PATH"
  installed "zsh as default shell"
else
  skipped "zsh as default shell (already set)"
fi

# ══════════════════════════════════════════════════════════════════
# 9. Stow dotfiles
# ══════════════════════════════════════════════════════════════════
section "Stow dotfiles"
info "Stowing dotfiles..."
cd "$DOTFILES"
stow ghostty aerospace hypr waybar foot btop brave gh zsh fastfetch mako fuzzel
installed "dotfiles (stow)"

# ══════════════════════════════════════════════════════════════════
# Post-install summary
# ══════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       macOS install complete!            ║${NC}"
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
echo "  3. Open System Settings → Privacy & Security → grant Accessibility to Aerospace"
echo "  4. aerospace reload-config"
echo "  5. Open Ghostty — JetBrainsMono Nerd Font should auto-load from config"
echo ""
warn "Note: Restart your terminal (or open a new one) to activate zsh + plugins."
warn "Note: If p10k prompt doesn't appear, run: p10k configure"
echo ""
