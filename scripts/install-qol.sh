#!/usr/bin/env bash
# install-qol.sh — one-shot privileged setup for the 2026-07-17 quality-of-life
# pass. Run:  sudo bash ~/dotfiles/scripts/install-qol.sh
#
# Design rules:
#   • Idempotent + reversible. Safe to re-run.
#   • Every dnf call carries --exclude=gdm. NEVER touches the display manager.
#   • NEVER flashes firmware (that stays an interactive `fwupdmgr update`).
#   • Does not use `set -e` — one failed optional step must not abort the rest.
set -uo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root:  sudo bash $0" >&2; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$(dirname "$SCRIPT_DIR")"
RUSER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"

say(){ printf '\n\033[1;34m══\033[0m %s\n' "$*"; }
ok(){  printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[1;33m!\033[0m %s\n' "$*"; }
DNF="dnf install -y --quiet --exclude=gdm"

# ── 1. Power: TLP → power-profiles-daemon (recommended on Fedora AMD) ─────────
# Reversible:  sudo dnf install tlp tlp-rdw && sudo systemctl enable --now tlp
#              && sudo dnf remove power-profiles-daemon
say "Power management → power-profiles-daemon"
# Remove TLP FIRST — its tlp-pd sub-package owns the same D-Bus service files as
# power-profiles-daemon, so ppd won't install while TLP is present.
if rpm -q tlp >/dev/null 2>&1 || rpm -q tlp-pd >/dev/null 2>&1; then
  systemctl disable --now tlp.service 2>/dev/null || true
  dnf remove -y --quiet tlp tlp-rdw tlp-pd 2>/dev/null || systemctl mask tlp.service
fi
rpm -q power-profiles-daemon >/dev/null 2>&1 || $DNF power-profiles-daemon
systemctl enable --now power-profiles-daemon.service 2>/dev/null || true
powerprofilesctl set balanced 2>/dev/null || true
ok "ppd active ($(powerprofilesctl get 2>/dev/null || echo '?')); tlp removed/disabled"

# ── 2. CLI tooling ───────────────────────────────────────────────────────────
say "CLI tools"
$DNF atuin git-delta direnv tealdeer duf procs du-dust
if ! command -v lazygit >/dev/null 2>&1; then
  dnf copr enable -y atim/lazygit 2>/dev/null && $DNF lazygit || warn "lazygit (copr) failed — skipping"
fi
sudo -u "$RUSER" tldr --update >/dev/null 2>&1 || true
sudo -u "$RUSER" atuin import auto >/dev/null 2>&1 || true
ok "installed: atuin delta lazygit direnv tealdeer duf procs dust"

# ── 3. Automatic updates (staged + security only, snapper-protected) ─────────
say "Automatic updates"
install -m 0755 "$DOTFILES/scripts/auto-update.sh" /usr/local/sbin/auto-update.sh
install -m 0644 "$DOTFILES/systemd/system/auto-update.service" /etc/systemd/system/auto-update.service
install -m 0644 "$DOTFILES/systemd/system/auto-update.timer"   /etc/systemd/system/auto-update.timer
systemctl daemon-reload
systemctl enable --now auto-update.timer
ok "auto-update.timer enabled (daily; stages all, applies security, updates flatpak)"

# ── 4. Firmware update metadata (fwupd) — NEVER auto-flashes ─────────────────
say "Firmware metadata refresh (fwupd)"
systemctl enable --now fwupd-refresh.timer 2>/dev/null || true
ok "fwupd-refresh.timer on. Apply firmware manually: fwupdmgr refresh && fwupdmgr update"

# ── 5. zram algorithm → zstd (better ratio, same RAM) ────────────────────────
say "zram → zstd"
install -d -m 0755 /etc/systemd
cat > /etc/systemd/zram-generator.conf <<'EOF'
# Managed by dotfiles/scripts/install-qol.sh
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
EOF
systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || warn "zram active next boot"
ok "zram compression = zstd"

# ── 6. GRUB menu timeout → 1s ────────────────────────────────────────────────
say "GRUB timeout → 1s"
if grep -q '^GRUB_TIMEOUT=' /etc/default/grub 2>/dev/null; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
else
  echo 'GRUB_TIMEOUT=1' >> /etc/default/grub
fi
if [[ -f /boot/grub2/grub.cfg ]]; then
  grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1 && ok "GRUB regenerated" \
    || warn "grub2-mkconfig failed — timeout applies after next manual regen"
else
  warn "no /boot/grub2/grub.cfg — skipped regen"
fi

say "DONE — privileged QoL setup complete."
printf '\nManual follow-ups (cannot be scripted safely):\n'
printf '  1. BIOS battery charge limit → 85%%  (reboot, F2/Framework setup, Power)\n'
printf '  2. Firmware:  fwupdmgr refresh && fwupdmgr update   (may reboot)\n'
printf '  3. atuin sync:  atuin register -u <name> -e <email>   (then `atuin login` on the PC)\n'
printf '  4. SSH key on GitHub:  gh ssh-key add ~/.ssh/id_ed25519.pub --type signing\n\n'
echo "Revert power daemon if desired: sudo dnf install tlp tlp-rdw && sudo systemctl enable --now tlp && sudo dnf remove power-profiles-daemon"
