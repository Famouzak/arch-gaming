#!/usr/bin/env bash

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[1/5] Updating system & installing official packages...${NC}"
sudo pacman -Syu --needed --noconfirm \
    git \
    base-devel \
    ttf-jetbrains-mono-nerd \
    starship \
    eza \
    bat \
    fastfetch \
    fzf

echo -e "${BLUE}[2/5] Checking ble.sh / AUR helper...${NC}"
if ! command -v yay &> /dev/null; then
    echo "Installing yay (AUR helper)..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
    rm -rf /tmp/yay
else
    echo ">>> yay already installed, skipping."
fi

yay -S --needed --noconfirm blesh-git

echo -e "${BLUE}[3/5] Setting up directories...${NC}"
mkdir -p ~/.config/alacritty

echo -e "${BLUE}[4/5] Writing configuration files...${NC}"

# 1. ~/.bashrc
cat << 'EOF' > ~/.bashrc
# ble.sh initialization
[[ $- == *i* ]] && source /usr/share/blesh/ble.sh

# Aliases
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --octal-permissions --group-directories-first'
alias tree='eza --tree --icons'
alias cat='bat --paging=never'
alias fetch='fastfetch'

# Starship prompt
eval "$(starship init bash)"
EOF

# 2. ~/.blerc
cat << 'EOF' > ~/.blerc
bleopt complete_auto_history=1
bleopt complete_auto_complete=1

ble-face command_builtin="fg=#89b4fa,bold"
ble-face command_alias="fg=#94e2d5"
ble-face command_function="fg=#cba6f7"
ble-face filename_directory="fg=#89b4fa,underline"
ble-face auto_complete="fg=#585b70,italic"
EOF

# 3. ~/.config/starship.toml
cat << 'EOF' > ~/.config/starship.toml
format = """
[░▒▓](#7aa2f7)\
[  ](bg:#7aa2f7 fg:#1d202f)\
[](fg:#7aa2f7 bg:#3b4261)\
$directory\
[](fg:#3b4261 bg:#7dcfff)\
$git_branch\
$git_status\
[](fg:#7dcfff bg:#bb9af7)\
$c$golang$node$rust$python$java\
[](fg:#bb9af7 bg:#24283b)\
$time\
[ ](fg:#24283b)\
$line_break$character"""

[directory]
style = "bg:#3b4261 fg:#eee5ff"
format = "[ $path ]($style)"
truncation_length = 3

[git_branch]
symbol = ""
style = "bg:#7dcfff fg:#15161e"
format = '[ $symbol $branch ]($style)'

[git_status]
style = "bg:#7dcfff fg:#15161e"
format = '[$all_status$ahead_behind ]($style)'

[time]
disabled = false
time_format = "%R"
style = "bg:#24283b fg:#787c99"
format = '[  $time ]($style)'

[character]
success_symbol = '[❯](bold #7aa2f7)'
error_symbol = '[❯](bold #f7768e)'
EOF

# 4. ~/.config/alacritty/alacritty.toml
cat << 'EOF' > ~/.config/alacritty/alacritty.toml
[font]
size = 11.0

[font.normal]
family = "JetBrainsMono Nerd Font"
style = "Regular"

[font.bold]
family = "JetBrainsMono Nerd Font"
style = "Bold"

[window]
padding = { x = 12, y = 12 }
opacity = 0.90
blur = true

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.cursor]
cursor = "#f5e0dc"
text = "#11111b"

[colors.normal]
black   = "#45475a"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#bac2de"

[colors.bright]
black   = "#585b70"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#a6adc8"
EOF

echo -e "${BLUE}[5/5] Reloading bash configuration...${NC}"
echo -e "${GREEN}Setup completed successfully! Restart your terminal or run 'source ~/.bashrc'${NC}"
