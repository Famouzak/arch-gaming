#!/bin/bash
set -e

# Load variabel from 01_install.sh
if [ -f /root/install_vars.sh ]; then
  source /root/install_vars.sh
else
  HOSTNAME="archlinux"
  USERNAME="famouzak"
fi

TIMEZONE="Asia/Jakarta"

echo "=== 1. Timezone, Locale & Hostname ==="
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# Setup /etc/hosts
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
EOF

echo "=== 2. Create Password for User & Root ==="
if ! id -u $USERNAME &>/dev/null; then
  useradd -m -G wheel,video,audio,storage,optical,input -s /bin/bash $USERNAME
fi

echo "Set password for user '$USERNAME':"
passwd $USERNAME
echo "Set password for root:"
passwd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo "=== 3. Optimize Pacman Config ==="
# [Enable] ParallelDownloads, Color, ILoveCandy
sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
grep -q "^ILoveCandy" /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf

echo "=== 4. Enable Multilib Repo ==="
sed -i "/\[multilib\]/,/Include/ s/^#//" /etc/pacman.conf

echo "=== 5. Drivers for AMD GPU, Audio PipeWire & KDE Plasma 6 ==="
# Arch Repository
pacman -Syu --noconfirm --needed \
  mesa lib32-mesa \
  vulkan-radeon lib32-vulkan-radeon \
  libva-mesa-driver lib32-libva-mesa-driver \
  lib32-vulkan-icd-loader vulkan-icd-loader vulkan-tools \
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol easyeffects lsp-plugins-lv2 calf alsa-utils \
  alacritty plasma-meta gwenview okular konsole dolphin kdeconnect kdenlive sddm wayland egl-wayland xdg-user-dirs \
  qt6-base qt6-declarative qt6-svg

echo "=== 6. Install & Setup SDDM Elegant Theme ==="
# Clean Up
rm -rf /tmp/elegant-sddm /usr/share/sddm/themes/elegant-archlinux /usr/share/sddm/themes/elegant-sddm

# Clone Repository 'elegant-archlinux'
git clone https://github.com/sniper1720/elegant-sddm-archlinux-theme.git /tmp/elegant-sddm
cp -r /tmp/elegant-sddm/elegant-archlinux /usr/share/sddm/themes/
rm -rf /tmp/elegant-sddm

# SDDM Configuration
mkdir -p /etc/sddm.conf.d
cat << 'EOF' > /etc/sddm.conf.d/theme.conf
[Theme]
Current=elegant-archlinux
EOF

echo "=== 7. Bootloader GRUB & Tools Snapper ==="
pacman -S --noconfirm --needed \
  grub efibootmgr grub-btrfs snapper snap-pac inotify-tools os-prober pacman-contrib

# Install HyperFluent Theme GRUB for Arch Linux
mkdir -p /boot/grub/themes
rm -rf /tmp/hyperfluent-grub /boot/grub/themes/HyperFluent
git clone --depth=1 https://github.com/Coopydood/HyperFluent-GRUB-Theme.git /tmp/hyperfluent-grub

# Copy 'arch' folder to Grub Theme
cp -r /tmp/hyperfluent-grub/arch /boot/grub/themes/HyperFluent
rm -rf /tmp/hyperfluent-grub

# 1. Set Timeout & Monitor Resolution
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
sed -i 's/^#GRUB_GFXMODE=.*/GRUB_GFXMODE=1920x1080x32,auto/' /etc/default/grub

# 2. Disable Sub Menu
sed -i 's/^#GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' /etc/default/grub
grep -q "^GRUB_DISABLE_SUBMENU=" /etc/default/grub || echo 'GRUB_DISABLE_SUBMENU=y' >> /etc/default/grub

# 3. Set to gfxterm mode
if grep -q "^#GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
  sed -i 's/^#GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' /etc/default/grub
elif ! grep -q "^GRUB_TERMINAL_OUTPUT=" /etc/default/grub; then
  echo 'GRUB_TERMINAL_OUTPUT="gfxterm"' >> /etc/default/grub
fi

# 4. Set Path for HyperFluent Theme
if grep -q "^GRUB_THEME=" /etc/default/grub; then
  sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/HyperFluent/theme.txt"|' /etc/default/grub
else
  echo 'GRUB_THEME="/boot/grub/themes/HyperFluent/theme.txt"' >> /etc/default/grub
fi

# 5. Set Kernel Zen as Default 
if grep -q "^GRUB_TOP_LEVEL=" /etc/default/grub; then
  sed -i 's|^GRUB_TOP_LEVEL=.*|GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"|' /etc/default/grub
else
  echo 'GRUB_TOP_LEVEL="/boot/vmlinuz-linux-zen"' >> /etc/default/grub
fi

# Early KMS for Btrfs & AMDGPU
sed -i 's/^MODULES=.*/MODULES=(btrfs amdgpu)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Install GRUB & Generate Config File
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo "=== 8. Enable Services ==="
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable grub-btrfsd

echo "=== 9. Preparation For Post-Install Script ==="
if [ -f /root/scripts/03_postinstall.sh ]; then
  cp /root/scripts/03_postinstall.sh /home/$USERNAME/
  chown $USERNAME:$USERNAME /home/$USERNAME/03_postinstall.sh
  chmod +x /home/$USERNAME/03_postinstall.sh
  echo "File 03_postinstall.sh is moved to /home/$USERNAME/"
fi

echo "=== Chroot Configuration Is Finished! ==="
echo "=== type 'exit' then 'reboot' ==="