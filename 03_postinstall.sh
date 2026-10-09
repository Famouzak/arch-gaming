#!/bin/bash
set -e

# Lokasi direktori tempat skrip ini berada (otomatis mendeteksi folder repo)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOTFILES_DIR="$SCRIPT_DIR/dotfiles"

# Pastikan skrip TIDAK dijalankan sebagai root/sudo
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Jangan jalankan skrip ini dengan sudo!"
  echo "Jalankan sebagai user biasa: ./03_postinstall.sh"
  exit 1
fi

echo "=== 1. Update Directory Default User (XDG) ==="
xdg-user-dirs-update

echo "=== 2. Install Tools Dasar (Base-Devel & Kernel Headers) ==="
sudo pacman -S --noconfirm --needed base-devel linux-zen-headers git

echo "=== 3. Install YAY (AUR Helper) ==="
if ! command -v yay &> /dev/null; then
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd ~
  rm -rf /tmp/yay
fi

echo "=== 4. Install Gaming & Streaming Tools (Official Repos) ==="
sudo pacman -S --noconfirm --needed \
  steam wine-staging winetricks \
  gamemode lib32-gamemode \
  mangohud lib32-mangohud goverlay lact \
  obs-studio ffmpeg vlc mpv gstreamer \
  gnutls lib32-gnutls giflib \
  v4l2loopback-dkms v4l2loopback-utils

echo "=== 5. Install Aplikasi AUR (Brave, Plasma Themes, Proton) ==="
yay -S --noconfirm --needed \
  brave-bin \
  darkly-bin \
  plasma6-applets-andromeda-launcher-git \
  protonup-qt \
  proton-ge-custom-bin \
  lib32-giflib

echo "=== 6. Enable Service LACT (Overclock & Fan Control AMD) ==="
sudo systemctl enable --now lactd

echo "=== 7. Konfigurasi Snapper (Btrfs Snapshots) ==="
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

echo "=== 8. Setup Hak Akses HDD WD Blue (/mnt/wdblue) ==="
if [ -d "/mnt/wdblue" ]; then
  sudo chown -R $USER:$USER /mnt/wdblue
fi

echo "=== 9. Setup Ocypus Gamma A40 Digital Cooler Display ==="
sudo pacman -S --noconfirm --needed python python-pip python-hidapi python-psutil

OCYPUS_SRC="/mnt/wdblue/ocypus-a40-digital-linux"

if [ -d "$OCYPUS_SRC" ]; then
  mkdir -p "$HOME/ocypus-a40-digital-linux"
  cp -r "$OCYPUS_SRC"/* "$HOME/ocypus-a40-digital-linux/"
  chmod +x "$HOME/ocypus-a40-digital-linux/ocypus-control.py"

  # Buat udev rule
  sudo bash -c 'cat > /etc/udev/rules.d/99-ocypus-a40.rules << EOF
# Ocypus Gamma A40 ARGB Digital - LCD & RGB Control
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1a2c", ATTRS{idProduct}=="434d", GROUP="input", MODE="0660"
EOF'

  sudo udevadm control --reload
  sudo udevadm trigger

  # Install & jalankan systemd service
  cd "$HOME/ocypus-a40-digital-linux"
  sudo ./ocypus-control.py install-service -u c -s k10temp -r 2.0 --model gamma
  sudo systemctl daemon-reload
  sudo systemctl enable --now ocypus-lcd.service
  cd ~
  echo "Ocypus LCD Display berhasil dikonfigurasi!"
else
  echo "Peringatan: Folder $OCYPUS_SRC tidak ditemukan di HDD. Setup Ocypus dilewati."
fi

echo "=== 10. Restorasi Dotfiles (KDE Plasma, Layout & Wallpaper) ==="
if [ -d "$DOTFILES_DIR" ]; then
  mkdir -p ~/.config ~/.local/share/wallpapers ~/.local/share/konsole

  # Restorasi Wallpaper
  if [ -f "$DOTFILES_DIR/wallpaper/favorite.jpg" ]; then
    cp "$DOTFILES_DIR/wallpaper/favorite.jpg" ~/.local/share/wallpapers/
  fi

  # Restorasi Konfigurasi Taskbar & Andromeda Launcher
  [ -f "$DOTFILES_DIR/plasma/plasma-org.kde.plasma.desktop-appletsrc" ] && cp "$DOTFILES_DIR/plasma/plasma-org.kde.plasma.desktop-appletsrc" ~/.config/
  [ -f "$DOTFILES_DIR/plasma/plasmashellrc" ] && cp "$DOTFILES_DIR/plasma/plasmashellrc" ~/.config/
  [ -f "$DOTFILES_DIR/plasma/kdeglobals" ] && cp "$DOTFILES_DIR/plasma/kdeglobals" ~/.config/

  # Restorasi Profil Konsole
  [ -f "$DOTFILES_DIR/konsole/konsolerc" ] && cp "$DOTFILES_DIR/konsole/konsolerc" ~/.config/
  if [ -d "$DOTFILES_DIR/konsole/profiles" ]; then
    cp -r "$DOTFILES_DIR/konsole/profiles/"* ~/.local/share/konsole/ 2>/dev/null || true
  fi

  # Apply Theme & Wallpaper via CLI
  plasma-apply-colorscheme Darkly || true
  if [ -f ~/.local/share/wallpapers/favorite.jpg ]; then
    plasma-apply-wallpaperimage ~/.local/share/wallpapers/favorite.jpg || true
  fi
else
  echo "Peringatan: Folder dotfiles tidak ditemukan di $DOTFILES_DIR. Ricing Plasma dilewati."
fi

echo "=== 11. Eksekusi Terminal Ricing (04_terminal.sh) ==="
if [ -f "$SCRIPT_DIR/04_terminal.sh" ]; then
  chmod +x "$SCRIPT_DIR/04_terminal.sh"
  "$SCRIPT_DIR/04_terminal.sh"
else
  echo "Peringatan: Skrip $SCRIPT_DIR/04_terminal.sh tidak ditemukan."
fi

echo "======================================================"
echo "=== Setup Post-Install Selesai! Sistem Siap Pakai. ==="
echo "======================================================"
