#!/bin/bash
set -e

# Run the Scrypt as User
if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Run as User not Root!"
  echo "Run as User: ./03_postinstall.sh"
  exit 1
fi

echo "=== 1. Update Directory Default User (XDG) ==="
xdg-user-dirs-update

echo "=== 2. Install YAY (AUR Helper) ==="
if ! command -v yay &> /dev/null; then
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd ~
  rm -rf /tmp/yay
fi

echo "=== 3. Install Gaming & Streaming Tools (Arch Repos) ==="
sudo pacman -S --noconfirm --needed \
  steam wine-staging winetricks \
  gamemode lib32-gamemode gamescope \
  mangohud lib32-mangohud goverlay lact \
  obs-studio obs-studio-plugin-browser ffmpeg vlc mpv gstreamer  \
  gnutls lib32-gnutls giflib \
  v4l2loopback-dkms v4l2loopback-utils

echo "=== 4. Install AUR Package ==="
yay -S --noconfirm --needed \
  brave-bin \
  darkly-bin \
  protonup-qt \
  proton-ge-custom-bin \
  lib32-giflib

echo "=== 5. Enable Service LACT (Overclock & Fan Control AMD) ==="
sudo systemctl enable --now lactd

echo "=== 6. Snapper Configuration (Btrfs Snapshots) ==="
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

echo "=== 7. Setup Access HDD WD Blue (/mnt/wdblue) ==="

if [ -d "/mnt/wdblue" ]; then
  sudo chown -R $USER:$USER /mnt/wdblue
fi

echo "=== 8. Setup Ocypus Gamma A40 Digital Cooler Display ==="
sudo pacman -S --noconfirm --needed python python-pip python-hid python-psutil

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

  # Install & Running systemd service
  cd "$HOME/ocypus-a40-digital-linux"
  sudo ./ocypus-control.py install-service -u c -s k10temp -r 2.0 --model gamma
  sudo systemctl daemon-reload
  sudo systemctl enable --now ocypus-lcd.service
  cd ~
  echo "Ocypus LCD Display running succesfully"
else
  echo "Warning: Folder $OCYPUS_SRC are not found. Setup Ocypus --Skipping."
fi

echo "=== 9. Cleanup Package Cache ==="

sudo paccache -rk1
sudo paccache -ruk0
yay -Sc --noconfirm || true
echo ">>> Package cache cleaned."

echo "======================================================"
echo "=== Setup Post-Install is Done! GLHF! ==="
echo "======================================================"
