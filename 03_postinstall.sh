#!/bin/bash
set -e

# Resolve repository and dotfiles directory path
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"

# Privilege check: Ensure script is NOT executed as root/sudo
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Do not execute this script with sudo/root privileges!"
  echo "Run as regular user: ./03_postinstall.sh"
  exit 1
fi

echo "=== 1. Initialize User Directories (XDG) ==="
xdg-user-dirs-update

echo "=== 2. Install Development Toolchain & Kernel Headers ==="
sudo pacman -S --noconfirm --needed base-devel linux-zen-headers git

echo "=== 3. Build & Install Yay AUR Helper ==="
if ! command -v yay &> /dev/null; then
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd ~
  rm -rf /tmp/yay
fi

echo "=== 4. Deploy Gaming & Streaming Software Stack (Official Repos) ==="
sudo pacman -S --noconfirm --needed \
  steam wine-staging winetricks \
  gamemode lib32-gamemode gamescope \
  mangohud lib32-mangohud goverlay lact \
  obs-studio obs-studio-plugin-browser ffmpeg vlc mpv gstreamer \
  gnutls lib32-gnutls giflib \
  v4l2loopback-dkms v4l2loopback-utils flatpak

echo "=== 5. Deploy AUR Packages (Brave, Desktop Themes, Proton) ==="
yay -S --noconfirm --needed \
  brave-bin \
  darkly-bin \
  protonup-qt \
  proton-ge-custom-bin \
  lib32-giflib

echo "=== Install Apps From Flatpak ==="
flatpak install flathub org.vinegarhq.Sober

echo "=== Install Andromeda Launcher Widget ==="
rm -rf /tmp/andromeda-launcher
git clone https://github.com/EliverLara/AndromedaLauncher.git /tmp/andromeda-launcher
kpackagetool6 -t Plasma/Applet -i /tmp/andromeda-launcher || kpackagetool6 -t Plasma/Applet -u /tmp/andromeda-launcher
rm -rf /tmp/andromeda-launcher

echo "=== 6. Enable LACT Service (AMD GPU Control) ==="
sudo systemctl enable --now lactd

echo "=== 7. Configure Snapper Btrfs Snapshot Automation ==="
sudo umount /.snapshots || true
sudo rm -rf /.snapshots
sudo snapper -c root create-config /
sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
sudo mkdir -p /.snapshots
sudo mount -a
sudo chmod 750 /.snapshots
sudo chown :wheel /.snapshots

sudo systemctl enable --now snapper-timeline.timer
sudo systemctl enable --now snapper-cleanup.timer
sudo snapper -c root set-config ALLOW_USERS=$USER SYNC_USER=yes

echo "=== 8. Set Ownership & Permissions for Secondary Storage ==="
if [ -d "/mnt/wdblue" ]; then
  sudo chown -R $USER:$USER /mnt/wdblue
fi

echo "=== 9. Deploy Ocypus Gamma A40 Digital Cooler Driver ==="
sudo pacman -S --noconfirm --needed python python-pip python-hid python-psutil

OCYPUS_SRC="/mnt/wdblue/ocypus-a40-digital-linux"

if [ -d "$OCYPUS_SRC" ]; then
  mkdir -p "$HOME/ocypus-a40-digital-linux"
  cp -r "$OCYPUS_SRC"/* "$HOME/ocypus-a40-digital-linux/"
  chmod +x "$HOME/ocypus-a40-digital-linux/ocypus-control.py"

  # Generate udev rule for USB device access
  sudo bash -c 'cat > /etc/udev/rules.d/99-ocypus-a40.rules << EOF
# Ocypus Gamma A40 ARGB Digital - LCD & RGB Control
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1a2c", ATTRS{idProduct}=="434d", GROUP="input", MODE="0660"
EOF'

  sudo udevadm control --reload
  sudo udevadm trigger

  # Install & activate systemd service
  cd "$HOME/ocypus-a40-digital-linux"
  sudo ./ocypus-control.py install-service -u c -s k10temp -r 2.0 --model gamma
  sudo systemctl daemon-reload
  sudo systemctl enable --now ocypus-lcd.service
  cd ~
  echo "Ocypus LCD Display successfully configured!"
else
  echo "WARNING: Directory $OCYPUS_SRC not found. Skipping Ocypus setup."
fi

echo "=== 10. Restore Desktop Dotfiles (KDE Plasma, Panel Layout, & Wallpaper) ==="
if [ -d "$DOTFILES_DIR" ]; then
  mkdir -p ~/.config ~/.local/share/wallpapers ~/.local/share/konsole

  # Restore Desktop Wallpaper
  if [ -f "$DOTFILES_DIR/wallpaper/favorite.jpg" ]; then
    cp "$DOTFILES_DIR/wallpaper/favorite.jpg" ~/.local/share/wallpapers/
  fi

  # Restore Panel, Launcher, & Desktop Configuration
  [ -f "$DOTFILES_DIR/plasma/plasma-org.kde.plasma.desktop-appletsrc" ] && cp "$DOTFILES_DIR/plasma/plasma-org.kde.plasma.desktop-appletsrc" ~/.config/
  [ -f "$DOTFILES_DIR/plasma/plasmashellrc" ] && cp "$DOTFILES_DIR/plasma/plasmashellrc" ~/.config/
  [ -f "$DOTFILES_DIR/plasma/kdeglobals" ] && cp "$DOTFILES_DIR/plasma/kdeglobals" ~/.config/

  # Restore Konsole Profiles & Color Schemes
  [ -f "$DOTFILES_DIR/konsole/konsolerc" ] && cp "$DOTFILES_DIR/konsole/konsolerc" ~/.config/
  if [ -d "$DOTFILES_DIR/konsole/profiles" ]; then
    cp -r "$DOTFILES_DIR/konsole/profiles/"* ~/.local/share/konsole/ 2>/dev/null || true
  fi

  # Apply Active Color Scheme & Wallpaper via CLI
  plasma-apply-colorscheme Darkly || true
  if [ -f ~/.local/share/wallpapers/favorite.jpg ]; then
    plasma-apply-wallpaperimage ~/.local/share/wallpapers/favorite.jpg || true
  fi
else
  echo "WARNING: Dotfiles directory not found at $DOTFILES_DIR. Skipping Plasma desktop deployment."
fi

echo "=== 11. Execute Terminal Ricing Script ==="
if [ -f "$SCRIPT_DIR/04_terminal.sh" ]; then
  chmod +x "$SCRIPT_DIR/04_terminal.sh"
  "$SCRIPT_DIR/04_terminal.sh"
elif [ -f "$SCRIPT_DIR/terminal.sh" ]; then
  chmod +x "$SCRIPT_DIR/terminal.sh"
  "$SCRIPT_DIR/terminal.sh"
else
  echo "WARNING: Terminal ricing script not found."
fi

echo "======================================================"
echo "=== Post-Install Deployment Complete! System Ready. ==="
echo "======================================================"
