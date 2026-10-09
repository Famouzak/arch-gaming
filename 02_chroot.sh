#!/bin/bash
set -e

# Import installation variables from Step 01
if [ -f /root/install_vars.sh ]; then
  source /root/install_vars.sh
else
  HOSTNAME="archlinux"
  USERNAME="famouzak"
fi

TIMEZONE="Asia/Jakarta"

echo "=== 1. System Localization & Network Identity ==="
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# Generate local loopback hosts mapping
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "=== 2. User Account Provisioning & Privilege Escalation ==="
if ! id -u $USERNAME &>/dev/null; then
  useradd -m -G wheel,video,audio,storage,optical,input -s /bin/bash $USERNAME
fi

echo "Set password for user '$USERNAME':"
passwd $USERNAME
echo "Set password for root:"
passwd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "=== 3. Package Manager Optimization & Multilib Repository ==="
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
grep -q "^ILoveCandy" /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/ s/^#//" /etc/pacman.conf
pacman -Sy

echo "=== 4. AMD Graphics Drivers, PipeWire Audio, & KDE Plasma 6 Desktop ==="
pacman -S --noconfirm --needed \
  git networkmanager pacman-contrib \
  mesa lib32-mesa \
  vulkan-radeon lib32-vulkan-radeon \
  libva-mesa-driver lib32-libva-mesa-driver \
  lib32-vulkan-icd-loader vulkan-icd-loader vulkan-tools \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol easyeffects lsp-plugins-lv2 calf alsa-utils \
  alacritty plasma-meta gwenview okular konsole dolphin kdeconnect kdenlive sddm wayland egl-wayland xdg-user-dirs \
  qt6-base qt6-declarative qt6-svg

echo "=== 5. SDDM Display Manager Theme Deployment ==="
# Clean temporary directories and legacy theme paths
rm -rf /tmp/elegant-sddm /usr/share/sddm/themes/elegant-archlinux /usr/share/sddm/themes/elegant-sddm

# Clone repository and stage the 'elegant-archlinux' theme
git clone https://github.com/sniper1720/elegant-sddm-archlinux-theme.git /tmp/elegant-sddm
cp -r /tmp/elegant-sddm/elegant-archlinux /usr/share/sddm/themes/
rm -rf /tmp/elegant-sddm

# Deploy SDDM configuration
mkdir -p /etc/sddm.conf.d
cat << 'EOF' > /etc/sddm.conf.d/theme.conf
[Theme]
Current=elegant-archlinux
EOF

echo "=== 6. GRUB Bootloader Configuration & Snapshot Tooling ==="
pacman -S --noconfirm --needed \
  grub efibootmgr grub-btrfs snapper snap-pac inotify-tools os-prober

# Deploy HyperFluent GRUB Theme (Arch Linux Variant)
mkdir -p /boot/grub/themes
rm -rf /tmp/hyperfluent-grub /boot/grub/themes/HyperFluent
git clone --depth=1 https://github.com/Coopydood/HyperFluent-GRUB-Theme.git /tmp/hyperfluent-grub
cp -r /tmp/hyperfluent-grub/arch /boot/grub/themes/HyperFluent
rm -rf /tmp/hyperfluent-grub

# Tune GRUB parameters
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
sed -i 's/^#GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080x32,auto/' /etc/default/grub

# Disable kernel submenu entries
sed -i 's/^#GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
grep -q "^GRUB_DISABLE_SUBMENU=" /etc/default/grub || echo 'GRUB_DISABLE_SUBMENU=y' >> /etc/default/grub

# Enable graphical terminal mode (gfxterm)
if grep -q "^#GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
  sed -i 's/^#GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' /etc/default/grub
elif ! grep -q "^GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
  echo 'GRUB_TERMINAL_OUTPUT="gfxterm"' >> /etc/default/grub
fi

# Set path for HyperFluent theme
if grep -q "^GRUB_THEME=" /etc/default/grub; then
  sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/HyperFluent/theme.txt"|' /etc/default/grub
else
  echo 'GRUB_THEME="/boot/grub/themes/HyperFluent/theme.txt"' >> /etc/default/grub
fi

# Pin Linux-Zen kernel as the primary boot choice
if grep -q "^GRUB_TOP_LEVEL=" /etc/default/grub; then
  sed -i 's|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"|' /etc/default/grub
else
  echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"' >> /etc/default/grub
fi

# Configure Early KMS for flicker-free Btrfs & AMDGPU boot
sed -i 's/^MODULES=.*/MODULES=(btrfs amdgpu)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Install GRUB bootloader & generate main configuration (Fallback Removable)
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== 7. Systemd Service Enablement ==="
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable grub-btrfsd

echo "=== 8. Post-Install Environment & Dotfiles Staging ==="
TARGET_DIR="/home/$USERNAME/arch-gaming"
mkdir -p "$TARGET_DIR"

# Stage repository contents (post-install scripts & dotfiles) to user home directory
if [ -d "/root/arch-gaming" ]; then
  cp -r /root/arch-gaming/* "$TARGET_DIR/"
elif [ -d "/root/scripts" ]; then
  cp -r /root/scripts/* "$TARGET_DIR/"
fi

# Assign user ownership and set executable permissions
chown -R $USERNAME:$USERNAME "$TARGET_DIR"
chmod +x "$TARGET_DIR"/*.sh 2>/dev/null || true

echo "=== Chroot Configuration Complete! ==="
