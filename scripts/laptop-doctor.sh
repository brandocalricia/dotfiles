#!/usr/bin/env bash
# laptop-doctor — one-shot health check for this Framework 13 (Fedora 44).
# Usage: bash ~/dotfiles/scripts/laptop-doctor.sh
# Checks: failed units, SELinux denials this boot, disk+snapshot space,
# btrfs health, battery health, pending .rpmnew/.rpmsave, pending updates.
# Deliberately NOT `set -e`: a diagnostic must keep running past a failing check.

DOTFILES="$HOME/dotfiles"
THEMES_DIR="$DOTFILES/themes"

# ── Theme (best-effort; falls back to the dynamic-theme palette if unavailable) ──
: "${GREEN:=94dbb2}" "${YELLOW:=d5db94}" "${RED:=ffb4ab}"
: "${ACCENT_PRIMARY:=adc6ff}" "${FG_DIM:=c3c6d3}"
theme="$(cat "$HOME/.config/current-theme" 2>/dev/null)"
if [ -n "$theme" ] && [ -f "$THEMES_DIR/$theme.sh" ]; then
    # shellcheck disable=SC1090
    . "$THEMES_DIR/$theme.sh" 2>/dev/null || true
fi

fg() { printf '\033[1m\033[38;2;%d;%d;%dm' "0x${1:0:2}" "0x${1:2:2}" "0x${1:4:2}"; }
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_OK=$(fg "$GREEN"); C_WARN=$(fg "$YELLOW"); C_CRIT=$(fg "$RED")
    C_HEAD=$(fg "$ACCENT_PRIMARY"); C_DIM=$(fg "$FG_DIM"); C_RST=$'\033[0m'
else
    C_OK=; C_WARN=; C_CRIT=; C_HEAD=; C_DIM=; C_RST=
fi

N_WARN=0; N_CRIT=0
hr()   { printf '\n%s── %s ──%s\n' "$C_HEAD" "$1" "$C_RST"; }
ok()   { printf '  %s✓%s %s\n' "$C_OK"   "$C_RST" "$*"; }
warn() { N_WARN=$((N_WARN+1)); printf '  %s!%s %s\n' "$C_WARN" "$C_RST" "$*"; }
crit() { N_CRIT=$((N_CRIT+1)); printf '  %s✗%s %s\n' "$C_CRIT" "$C_RST" "$*"; }
info() { printf '  %s·%s %s\n' "$C_DIM"  "$C_RST" "$*"; }
list() { printf '      %s\n' "$@"; }

# ── sudo: prime once for the root-only checks (SELinux, btrfs, snapshots) ──
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
    printf '%slaptop-doctor needs sudo for the SELinux/btrfs/snapshot checks.%s\n' "$C_DIM" "$C_RST"
    sudo -v 2>/dev/null || printf '%s(sudo unavailable — those checks will be skipped)%s\n' "$C_DIM" "$C_RST"
fi
srun() { if [ -z "$SUDO" ] || sudo -n true 2>/dev/null; then $SUDO "$@" 2>/dev/null; else return 127; fi; }

printf '%s laptop-doctor%s  %s · %s · kernel %s\n' "$C_HEAD" "$C_RST" "$(date '+%a %d %b %H:%M')" "$(hostnamectl hostname 2>/dev/null || hostname)" "$(uname -r)"

# ── 1. failed systemd units ──────────────────────────────────────────────────
hr "systemd units"
sf=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
[ -z "$sf" ] && ok "no failed system units" || { crit "failed system units:"; list $sf; }
uf=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
[ -z "$uf" ] && ok "no failed user units" || { crit "failed user units:"; list $uf; }

# ── 2. SELinux denials this boot (greetd/xdm_t history — see SETUP-NOTES) ─────
hr "SELinux denials (this boot)"
avc=$(srun ausearch -m avc,user_avc -ts boot | grep 'denied' || true)
ndenied=$(printf '%s\n' "$avc" | grep -c denied)
if [ -z "$avc" ]; then
    ok "no AVC denials since boot"
elif printf '%s\n' "$avc" | grep -q 'xdm_t'; then
    crit "$ndenied denial(s) incl. xdm_t — greetd/SELinux regression may be back (SETUP-NOTES greetd section):"
    printf '%s\n' "$avc" | grep 'xdm_t' | tail -5 | sed 's/^/      /'
else
    warn "$ndenied denial(s), none xdm_t — likely the known tlp_t 'ps' / snapperd baseline (SETUP-NOTES):"
    printf '%s\n' "$avc" | tail -4 | sed 's/^/      /'
fi

# ── 3. disk & snapshots ──────────────────────────────────────────────────────
hr "disk & snapshots"
read -r used avail pct < <(df -h --output=used,avail,pcent / | tail -1)
dnum=$(printf '%s' "$pct" | tr -dc '0-9')
msg="root: $used used, $avail free ($pct)"
[ "${dnum:-0}" -ge 85 ] && warn "$msg" || info "$msg"
fe=$(srun btrfs filesystem usage / | awk '/Free \(estimated\)/{print $3; exit}')
[ -n "$fe" ] && info "btrfs free (estimated): $fe"
sc=$(srun snapper -c root list | grep -cE '^[0-9]')
[ -n "$sc" ] && info "snapper 'root' snapshots (incl. current): ${sc:-?}"

# ── 4. btrfs filesystem health ───────────────────────────────────────────────
hr "btrfs filesystem health"
stats=$(srun btrfs device stats /)
if [ -z "$stats" ]; then
    info "device stats unavailable (need sudo)"
elif printf '%s\n' "$stats" | awk '{s+=$2} END{exit (s>0)}'; then
    ok "no device errors (all counters 0)"
else
    crit "btrfs device error counters non-zero:"
    printf '%s\n' "$stats" | grep -vE '\s0$' | sed 's/^/      /'
fi
scrub=$(srun btrfs scrub status / | awk -F: '/Status/{gsub(/^[ \t]+/,"",$2);print $2}')
[ -n "$scrub" ] && info "last scrub: $scrub"

# ── 5. battery health (Framework BAT1: charge_* in µAh) ──────────────────────
hr "battery (BAT1)"
B=/sys/class/power_supply/BAT1
if [ -r "$B/charge_full" ] && [ -r "$B/charge_full_design" ]; then
    cf=$(cat "$B/charge_full"); cfd=$(cat "$B/charge_full_design")
    cyc=$(cat "$B/cycle_count" 2>/dev/null); cap=$(cat "$B/capacity" 2>/dev/null)
    st=$(cat "$B/status" 2>/dev/null)
    health=$(awk -v a="$cf" -v b="$cfd" 'BEGIN{printf "%.0f", a/b*100}')
    mah=$(awk -v a="$cf" -v b="$cfd" 'BEGIN{printf "%d/%d", a/1000, b/1000}')
    m="health ${health}% of design (${mah} mAh) · ${cyc} cycles · ${cap}% charged · ${st}"
    if [ "$health" -ge 80 ]; then ok "$m"; elif [ "$health" -ge 60 ]; then warn "$m"; else crit "$m"; fi
else
    info "BAT1 charge attributes not readable"
fi

# ── 6. pending config merges (.rpmnew / .rpmsave) ────────────────────────────
hr "pending config merges"
rn=$(srun find /etc -xdev \( -name '*.rpmnew' -o -name '*.rpmsave' -o -name '*.rpmorig' \))
if [ -z "$rn" ]; then
    ok "no .rpmnew/.rpmsave under /etc"
else
    warn "config files awaiting review:"
    printf '%s\n' "$rn" | sed 's/^/      /'
    if printf '%s\n' "$rn" | grep -q '/etc/pam.d/greetd'; then
        crit "↳ greetd PAM .rpmnew present — DO NOT blind-merge; the SELinux/login fix lives here (SETUP-NOTES greetd section)"
    fi
fi
info "reminder: the internal-mic fix /etc/wireplumber/.../fw13-mic.conf is untracked — verify it survives wireplumber updates"

# ── 7. pending dnf updates (snapshotted automatically when you upgrade) ───────
hr "pending updates"
upd=$(timeout 40 dnf -q check-upgrade 2>/dev/null | grep -cE '^[a-zA-Z0-9]')
if [ "${upd:-0}" -eq 0 ]; then
    ok "system up to date (or offline)"
else
    info "$upd update(s) available — 'sudo dnf upgrade' (auto pre/post snapshot)"
fi

# ── summary ──────────────────────────────────────────────────────────────────
hr "summary"
if [ "$N_CRIT" -gt 0 ]; then
    crit "$N_CRIT critical, $N_WARN warning(s) — see above"
elif [ "$N_WARN" -gt 0 ]; then
    warn "$N_WARN warning(s), no critical issues"
else
    ok "all clear"
fi
echo
