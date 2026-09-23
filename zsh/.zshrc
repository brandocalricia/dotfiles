# Width-aware fetch, on demand (`ff`). A new terminal starts blank.
# Side-by-side (logo left, info right) needs ~82 cols before the info column
# wraps; below that, stack the logo on top. The 29-col logo plus the longest
# info line is the 82.
ff() {
  command -v fastfetch >/dev/null 2>&1 || return 0
  if [[ ${COLUMNS:-80} -lt 82 ]]; then fastfetch --logo-position top
  else fastfetch; fi
}
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off
typeset -g POWERLEVEL9K_DISABLE_INSTANT_PROMPT=true

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME=""

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zoxide)

source $ZSH/oh-my-zsh.sh

# User configuration

# QoL aliases (post-migration to Fedora)
alias cat='bat --paging=never'
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first --git'
alias la='eza -la --icons --group-directories-first --git'
alias find='fd'

# Rocket League OFFLINE training with BakkesMod (-noeac). Online ranked/casual
# stays on the Heroic Play button, untouched.
alias rl-train='$HOME/.local/bin/rl-train.sh'

eval "$(zoxide init zsh)"
[ -f /usr/share/fzf/shell/key-bindings.zsh ] && source /usr/share/fzf/shell/key-bindings.zsh

# One line. Dim path, dim git branch inside a repo, ❯. Red ❯ after a failed
# command. No frame and no right prompt. Mac stays a single character.
autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats '%F{245}%b%f'
zstyle ':vcs_info:git:*' actionformats '%F{245}%b|%a%f'
precmd_functions+=(vcs_info)
setopt PROMPT_SUBST
if [[ "$(uname -s)" == Darwin ]]; then
  PROMPT='❯ '
else
  PROMPT='%F{245}%~%f${vcs_info_msg_0_:+ $vcs_info_msg_0_} %(?.%F{255}❯%f.%F{196}❯%f) '
fi
RPROMPT=

# uv env loader (uncomment after installing uv)
# . "$HOME/.local/bin/env"

# Generated for envman. Do not edit.
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"

# Go binaries
export PATH=$PATH:$HOME/go/bin

export PATH="$HOME/.npm-global/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"

# Rocket League BakkesMod training
alias rl-train='$HOME/.local/bin/rl-train.sh'
alias rl-map-extract='$HOME/.local/bin/rl-map-extract.sh'
alias rl-map-download='$HOME/.local/bin/rl-map-download.sh'

# Cross-machine work awareness (Syncthing-shared ~/code heartbeats)
alias work-status='$HOME/dotfiles/scripts/work-status.sh'

# Grok Build wrapper. `command grok` skips the function.
#
# Never give the agent $HOME (or the old ~/Brain clone) as cwd — Grok 0.2.93
# tarball blast radius. A fresh terminal starts in ~; type `grok` anyway.
# Your shell stays put; only the agent process is launched from ~/grok-sandbox.
# If you already `cd`'d into a project, that project stays the cwd.
# Obsidian is a manual notebook — do not regenerate vault context here.
grok() {
  if [ "${1-}" = "trace" ]; then
    local has_local=0 a
    for a in "$@"; do
      [ "$a" = "--local" ] && has_local=1
    done
    if [ "$has_local" -eq 0 ]; then
      echo "grok wrapper: refusing remote trace upload; adding --local" >&2
      set -- "$@" --local
    fi
  fi
  local launch_cwd="$PWD"
  local home_abs="${HOME:A}"
  local here="${PWD:A}"
  local sandbox="$HOME/grok-sandbox"
  case "$here" in
    "$home_abs"|"$home_abs/Brain"|"$home_abs/Brain.linux-mint-archive-2026-05"|"$home_abs/Brain.linux-mint-archive-2026-05"/*)
      mkdir -p "$sandbox"
      launch_cwd="$sandbox"
      echo "grok wrapper: launching in ~/grok-sandbox (agent cwd; your shell stays in ${PWD/#$HOME/~})" >&2
      ;;
  esac
  # So the done-notify hook can tell *this* Terminal tab from another Grok.
  local launch_tty="${TTY:-}"
  (cd "$launch_cwd" && GROK_TTY="$launch_tty" command grok "$@")
}

# ── QoL tooling (2026-07-17) ─────────────────────────────────────────────────
# Each guarded so the shell still starts fine on a machine missing the tool.
alias lg='lazygit'
command -v dust >/dev/null 2>&1 && alias du='dust'      # tree-style disk usage
command -v duf  >/dev/null 2>&1 && alias df='duf'       # prettier df
command -v procs >/dev/null 2>&1 && alias ps='procs'    # modern ps
# direnv — per-project env auto-loading
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
# atuin — encrypted, cross-machine shell history (binds Ctrl-R + Up).
# Sourced LAST so it wins the Ctrl-R binding over fzf/oh-my-zsh.
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"

# jot — capture a thought into Obsidian from anywhere: jot buy cables
jot() { "$HOME/dotfiles/scripts/jot.sh" "$@"; }
export YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket"

# Local secrets — deliberately OUTSIDE ~/dotfiles, which auto-commits and pushes
# every 15 minutes. Never put a key in the dotfiles repo. chmod 600.
[ -f ~/.config/secrets.env ] && source ~/.config/secrets.env

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<
