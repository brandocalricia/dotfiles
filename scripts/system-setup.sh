#!/usr/bin/env bash
# Privileged system setup — run once with:  sudo bash ~/dotfiles/scripts/system-setup.sh
# Covers: performance tuning, dev tools, Docker, logind/lid behavior
#
# DISPLAY MANAGER: intentionally skipped.
# This machine uses SDDM. Nothing here touches /etc/systemd/system/display-manager.service
# or installs gdm/gdm3/sddm/lightdm. Do not add such steps.

set -e
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
section() { echo -e "\n${BLUE}══${NC} $1 ${BLUE}══${NC}"; }

REAL_USER="${SUDO_USER:-$USER}"

# Guard: refuse to run if someone added display-manager steps back in
if grep -qEi 'gdm|display.manager\.service|sddm|lightdm' "$0" 2>/dev/null | grep -v '# '; then
  echo "ERROR: display-manager references found in script — aborting." >&2
  exit 1
fi

# ══════════════════════════════════════════════════════════════════
# Performance
# ══════════════════════════════════════════════════════════════════
section "Swappiness"
echo "vm.swappiness=10" > /etc/sysctl.d/99-laptop.conf
sysctl -w vm.swappiness=10
info "swappiness set to 10 (was 60)"

section "fstrim"
systemctl enable --now fstrim.timer
info "fstrim.timer already enabled — confirmed active"

section "cpupower (schedutil governor)"
dnf install -y --exclude=gdm --exclude=gdm3 kernel-tools
cat > /etc/sysconfig/cpupower << 'EOF'
CPUPOWER_START_OPTS="frequency-set --governor schedutil"
CPUPOWER_STOP_OPTS="frequency-set --governor ondemand"
EOF
systemctl enable --now cpupower.service
info "cpupower set to schedutil governor"

# ══════════════════════════════════════════════════════════════════
# Lid / power button behavior
# ══════════════════════════════════════════════════════════════════
section "logind: lid close + power button"
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/laptop.conf << 'EOF'
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandlePowerKey=lock
EOF
systemctl restart systemd-logind
info "logind configured: lid=suspend, power-button=lock"

# ══════════════════════════════════════════════════════════════════
# Dev tools
# ══════════════════════════════════════════════════════════════════
section "GCC / build tools"
dnf install -y --exclude=gdm --exclude=gdm3 gcc gcc-c++ make
info "gcc, g++, make installed"

section "Java JDK 21"
dnf install -y --exclude=gdm --exclude=gdm3 java-21-openjdk java-21-openjdk-devel
alternatives --set java /usr/lib/jvm/java-21-openjdk-$(uname -m)/bin/java 2>/dev/null || \
  alternatives --set java $(alternatives --list 2>/dev/null | grep java-21 | head -1 | awk '{print $3}') 2>/dev/null || \
  warn "Could not auto-set java alternative — run: sudo alternatives --config java"
info "JDK 21 installed. Existing JDK 25 is still present."

section "pipx"
dnf install -y --exclude=gdm --exclude=gdm3 python3-pipx
info "pipx installed"

# ══════════════════════════════════════════════════════════════════
# NOTE: Docker, VSCode, Go, and powertop are intentionally omitted.
# Run those individually — see the comment block at the top of this
# file for context (display-manager incident).
# ══════════════════════════════════════════════════════════════════

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         system-setup.sh complete                ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Manual steps remaining:"
echo "  1. Install Docker:   sudo dnf install -y --exclude=gdm moby-engine docker-compose"
echo "  2. Install VSCode:   (add MS repo, then) sudo dnf install -y --exclude=gdm code"
echo "  3. Install Go:       sudo dnf install -y --exclude=gdm golang"
echo "  4. Install powertop: sudo dnf install -y --exclude=gdm powertop"
echo "  5. Log out / back in → Docker group takes effect"
echo ""
echo "NOTE: Hibernate is NOT configured — your swap is zram-only (RAM-backed)."
