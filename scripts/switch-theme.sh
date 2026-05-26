#!/usr/bin/env bash
# Usage: bash ~/dotfiles/scripts/switch-theme.sh <theme>

set -e
THEME="$1"
DOTFILES="$HOME/dotfiles"
THEMES_DIR="$DOTFILES/themes"

if [ -z "$THEME" ]; then
    echo "Available: $(ls $THEMES_DIR/*.sh | xargs -n1 basename | sed 's/.sh//' | tr '\n' ' ')"
    exit 1
fi

if [ ! -f "$THEMES_DIR/$THEME.sh" ]; then
    echo "Theme '$THEME' not found."
    exit 1
fi

source "$THEMES_DIR/$THEME.sh"
echo "Switching to: $THEME_NAME"

# ── Hyprland borders ─────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
    sed -i "s/col.active_border = rgba([^)]*) rgba([^)]*) 45deg/col.active_border = rgba(${BORDER_ACTIVE_1}ff) rgba(${BORDER_ACTIVE_2}ff) 45deg/" "$HYPR_CONF"
    sed -i "s/col.inactive_border = rgba([^)]*)/col.inactive_border = rgba(${BORDER_INACTIVE}aa)/" "$HYPR_CONF"
    hyprctl reload
fi

# ── Waybar CSS (hex only, no rgb conversion) ──────────────────────
if [[ "$(uname)" == "Linux" ]]; then
cat > "$HOME/.config/waybar/style.css" << EOF
* {
    font-family: "JetBrainsMono Nerd Font", "JetBrainsMono NF", "Font Awesome 6 Free", monospace;
    font-size: 13px;
    font-weight: 500;
    min-height: 0;
    border: none;
    border-radius: 0;
}
window#waybar {
    background: transparent;
    color: #${FG_DIM};
}
.modules-left, .modules-center, .modules-right {
    background: #${BAR_BG};
    border: 1px solid #${BAR_BORDER};
    border-radius: 10px;
    margin: 6px 4px;
    padding: 0 6px;
}
#workspaces { padding: 0 4px; }
#workspaces button {
    padding: 0 8px;
    margin: 4px 2px;
    color: #${BAR_INACTIVE_WS};
    background: transparent;
    border-radius: 6px;
    transition: all 0.2s ease;
}
#workspaces button.active {
    color: #${BG_DARK};
    background: #${ACCENT_PRIMARY};
}
#workspaces button.urgent {
    color: #${BG_DARK};
    background: #${RED};
}
#workspaces button:hover {
    background: #${BG_LIGHT};
    color: #${FG_BRIGHT};
}
#clock {
    padding: 0 14px;
    color: #${ACCENT_PRIMARY};
    font-weight: 600;
}
#cpu, #memory, #disk, #network, #pulseaudio, #tray {
    padding: 0 10px;
    margin: 4px 3px;
    background: #${BG_MID};
    color: #${FG_DIM};
    border-radius: 6px;
    transition: all 0.2s ease;
}
#cpu:hover, #memory:hover, #disk:hover, #network:hover, #pulseaudio:hover {
    background: #${BG_LIGHT};
}
#cpu { color: #${YELLOW}; }
#memory { color: #${ORANGE}; }
#disk { color: #${PURPLE}; }
#network { color: #${GREEN}; }
#pulseaudio { color: #${TEAL}; }
#pulseaudio.muted { color: #${RED}; }
#tray { padding: 0 8px; }
tooltip {
    background: #${BG_DARK};
    border: 1px solid #${BG_LIGHTER};
    border-radius: 8px;
    color: #${FG_BRIGHT};
    padding: 4px;
}
EOF
fi

# ── foot terminal ─────────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
cat > "$HOME/.config/foot/foot.ini" << EOF
font=JetBrainsMono Nerd Font:size=11
pad=12x12
dpi-aware=yes

[cursor]
style=beam

[colors-dark]
alpha=0.95
background=${BG_DARK}
foreground=${FG_DIM}
selection-background=${BG_LIGHT}
selection-foreground=${FG_BRIGHT}
regular0=${BG_MID}
regular1=${RED}
regular2=${GREEN}
regular3=${YELLOW}
regular4=${ACCENT_SECONDARY}
regular5=${PURPLE}
regular6=${TEAL}
regular7=${FG_MID}
bright0=${BG_LIGHTER}
bright1=${RED}
bright2=${GREEN}
bright3=${YELLOW}
bright4=${ACCENT_PRIMARY}
bright5=${PURPLE}
bright6=${ACCENT_PRIMARY}
bright7=${FG_BRIGHT}
EOF
fi

# ── Ghostty terminal ─────────────────────────────────────────────
GHOSTTY_THEMES_DIR="$HOME/.config/ghostty/themes"
GHOSTTY_CONF="$HOME/.config/ghostty/config"
mkdir -p "$GHOSTTY_THEMES_DIR"
cat > "$GHOSTTY_THEMES_DIR/$THEME" << EOF
palette = 0=#${BG_MID}
palette = 1=#${RED}
palette = 2=#${GREEN}
palette = 3=#${YELLOW}
palette = 4=#${ACCENT_SECONDARY}
palette = 5=#${PURPLE}
palette = 6=#${TEAL}
palette = 7=#${FG_MID}
palette = 8=#${BG_LIGHTER}
palette = 9=#${RED}
palette = 10=#${GREEN}
palette = 11=#${YELLOW}
palette = 12=#${ACCENT_PRIMARY}
palette = 13=#${PURPLE}
palette = 14=#${ACCENT_PRIMARY}
palette = 15=#${FG_BRIGHT}
background = #${BG_DARK}
foreground = #${FG_DIM}
cursor-color = #${ACCENT_PRIMARY}
selection-background = #${BG_LIGHT}
selection-foreground = #${FG_BRIGHT}
EOF
sed -i "s/^theme = .*/theme = ${THEME}/" "$GHOSTTY_CONF"

# ── hyprlock ──────────────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
cat > "$HOME/.config/hypr/hyprlock.conf" << EOF
background {
    monitor =
    path = screenshot
    blur_passes = 3
    blur_size = 8
    contrast = 0.9
    brightness = 0.8
}
input-field {
    monitor =
    size = 280, 56
    outline_thickness = 2
    dots_size = 0.28
    dots_spacing = 0.35
    dots_center = true
    outer_color = rgba(${ACCENT_PRIMARY}ff)
    inner_color = rgba(${BG_DARK}b3)
    font_color = rgba(${FG_DIM}ff)
    fade_on_empty = false
    placeholder_text = <i>password...</i>
    hide_input = false
    rounding = 12
    check_color = rgba(${GREEN}ff)
    fail_color = rgba(${RED}ff)
    position = 0, -140
    halign = center
    valign = center
}
label {
    monitor =
    text = cmd[update:1000] date "+%I:%M %p"
    color = rgba(${FG_BRIGHT}ff)
    font_size = 110
    font_family = JetBrainsMono Nerd Font ExtraBold
    position = 0, 120
    halign = center
    valign = center
}
label {
    monitor =
    text = cmd[update:60000] date "+%A, %B %d"
    color = rgba(${ACCENT_PRIMARY}ff)
    font_size = 22
    font_family = JetBrainsMono Nerd Font
    position = 0, 30
    halign = center
    valign = center
}
label {
    monitor =
    text = \$USER
    color = rgba(${FG_DIM}e6)
    font_size = 16
    font_family = JetBrainsMono Nerd Font
    position = 0, -240
    halign = center
    valign = center
}
EOF
fi

# ── Fix GTK CSS alpha + restart waybar ───────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    sed -i "s/background: #\([0-9a-fA-F]\{6\}\)ee;/background: alpha(#\1, 0.93);/g" "$HOME/.config/waybar/style.css"
    sed -i "s/background: #\([0-9a-fA-F]\{6\}\)99;/background: alpha(#\1, 0.60);/g" "$HOME/.config/waybar/style.css"
    sed -i "s/background: #\([0-9a-fA-F]\{6\}\)fa;/background: alpha(#\1, 0.98);/g" "$HOME/.config/waybar/style.css"
    pkill waybar 2>/dev/null; sleep 1 && waybar &>/dev/null & disown
fi

# ── Mako notifications ────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    mkdir -p "$HOME/.config/mako"
    cat > "$HOME/.config/mako/config" << EOF
background-color=#${BG_DARK}ff
text-color=#${FG_BRIGHT}ff
border-color=#${ACCENT_PRIMARY}ff
border-size=2
border-radius=8
padding=12
margin=8
default-timeout=5000
max-visible=5
EOF
    makoctl reload 2>/dev/null || true
fi

# ── btop ──────────────────────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    BTOP_THEMES_DIR="$HOME/.config/btop/themes"
    mkdir -p "$BTOP_THEMES_DIR"
    if [ -f "$DOTFILES/btop/.config/btop/themes/$THEME.theme" ]; then
        cp "$DOTFILES/btop/.config/btop/themes/$THEME.theme" "$BTOP_THEMES_DIR/active.theme"
    fi
    BTOP_CONF="$HOME/.config/btop/btop.conf"
    if [ -f "$BTOP_CONF" ]; then
        if grep -q "^color_theme" "$BTOP_CONF"; then
            sed -i 's/^color_theme.*$/color_theme = "active"/' "$BTOP_CONF"
        else
            echo 'color_theme = "active"' >> "$BTOP_CONF"
        fi
    fi
fi

# ── Fuzzel app launcher ───────────────────────────────────────────
if [[ "$(uname)" == "Linux" ]]; then
    mkdir -p "$HOME/.config/fuzzel"
    cat > "$HOME/.config/fuzzel/fuzzel.ini" << EOF
[main]
font=JetBrainsMono Nerd Font:size=13
width=30
lines=8
tabs=2
horizontal-pad=20
vertical-pad=10
inner-pad=8

[colors]
background=${BG_DARK}ff
text=${FG_DIM}ff
match=${ACCENT_PRIMARY}ff
selection=${BG_LIGHT}cc
selection-text=${FG_BRIGHT}ff
border=${ACCENT_PRIMARY}ff

[border]
width=2
radius=8
EOF
    pkill fuzzel 2>/dev/null || true
fi

# ── Fastfetch keyColor ────────────────────────────────────────────
FASTFETCH_CONF="$HOME/.config/fastfetch/config.jsonc"
if [ -f "$FASTFETCH_CONF" ]; then
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/\"color\": \"#[0-9a-fA-F]*\"/\"color\": \"#${ACCENT_PRIMARY}\"/" "$FASTFETCH_CONF"
    else
        sed -i "s/\"color\": \"#[0-9a-fA-F]*\"/\"color\": \"#${ACCENT_PRIMARY}\"/" "$FASTFETCH_CONF"
    fi
fi

# ── Save current theme ────────────────────────────────────────────
echo "$THEME" > "$HOME/.config/current-theme"

echo "✓ Switched to: $THEME_NAME"
echo "  borders reloaded · waybar restarted · foot updated · ghostty updated · hyprlock updated"
echo "  mako updated · btop theme updated · fuzzel updated · fastfetch updated"
