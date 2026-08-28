# macOS Terminal.app Resume restores previous-session scrollback via
# /etc/zshrc_Apple_Terminal. That file runs *before* ~/.zshrc, so this
# must live in .zshenv. Fedora is unaffected (TERM_SESSION_ID is unset).
if [[ "$(uname -s)" == Darwin ]]; then
  export SHELL_SESSIONS_DISABLE=1
fi
