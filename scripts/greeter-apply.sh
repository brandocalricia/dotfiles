#!/bin/sh
# Apply the staged tuigreet theme to /etc/greetd/config.toml. ROOT REQUIRED.
# Run as:  sudo sh ~/dotfiles/scripts/greeter-apply.sh
# Scope: this script touches ONLY the --theme argument of the tuigreet
# command line in config.toml. Never PAM, never vt/user, never other files.
# Rollback: sudo cp /etc/greetd/config.toml.pre-theme-backup /etc/greetd/config.toml

set -eu
CONF=/etc/greetd/config.toml
BACKUP=$CONF.pre-theme-backup
STAGED="/home/${SUDO_USER:-$USER}/.cache/dynamic-theme/tuigreet.txt"

[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
[ -f "$STAGED" ] || { echo "nothing staged at $STAGED" >&2; exit 1; }
theme=$(head -n1 "$STAGED" | tr -d '[:space:]')

# Validate: strictly component=color pairs from fixed whitelists
echo "$theme" | grep -Eq '^[a-z]+=[a-z]+(;[a-z]+=[a-z]+)*$' || {
    echo "staged string malformed, refusing: $theme" >&2; exit 1; }
for pair in $(echo "$theme" | tr ';' ' '); do
    comp=${pair%%=*}; col=${pair##*=}
    case "$comp" in
        text|time|container|border|title|greet|prompt|input|action|button) ;;
        *) echo "unknown component '$comp', refusing" >&2; exit 1 ;;
    esac
    case "$col" in
        black|red|green|yellow|blue|magenta|cyan|gray|darkgray|white|\
        lightred|lightgreen|lightyellow|lightblue|lightmagenta|lightcyan) ;;
        *) echo "unknown color '$col', refusing" >&2; exit 1 ;;
    esac
done

grep -cq '^command = .*tuigreet' "$CONF" || {
    echo "no tuigreet command line in $CONF, refusing" >&2; exit 1; }

[ -f "$BACKUP" ] || { cp "$CONF" "$BACKUP"; echo "backup: $BACKUP"; }

if grep -q -- "--theme '[^']*'" "$CONF"; then
    sed -i "s|--theme '[^']*'|--theme '$theme'|" "$CONF"
else
    sed -i "s|tuigreet |tuigreet --theme '$theme' |" "$CONF"
fi

echo "applied. resulting line:"
grep '^command' "$CONF"
