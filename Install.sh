#!/usr/bin/env bash
# 01-install.sh - Arch Linux gaming + streaming installer (UEFI only)
# Target: Ryzen 5 5600 / RX 5700 XT / B550M-K / NVMe 256GB (+ optional HDD for games)
# Run from the Arch ISO live environment, as root, with internet connected.
set -euo pipefail

############ EDIT THESE ############
DISK="/dev/nvme0n1"      # system disk (WILL BE ERASED) - check with lsblk first
HDD=""                   # e.g. /dev/sda -> formatted ext4, mounted at /mnt/storage (ERASED). Empty = skip
HOST="archgame"
USERNAME="famo"
TIMEZONE="Asia/Jakarta"
KEYMAP="us"
####################################

die() { echo "ERROR: $*" >&2; exit 1; }
part() { [[ $1 == *nvme* || $1 == *mmcblk* ]] && echo "${1}p${2}" || echo "${1}${2}"; }

[[ $EUID -eq 0 ]] || die "Run as root"
[[ -d /sys/firmware/efi/efivars ]] || die "Not booted in UEFI mode (enable UEFI / disable CSM in BIOS)"
ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "No internet connection"

lsblk -o NAME,SIZE,MODEL,TYPE,MOUNTPOINTS
echo
echo "!!! $DISK will be completely ERASED !!!"
read -rp "Type the disk path again to confirm: " c
[[ $c == "$DISK" ]] || die "Confirmation failed"
if [[ -n $HDD ]]; then
  echo "!!! $HDD will ALSO be completely ERASED !!!"
  read -rp "Type the HDD path again to confirm: " c
  [[ $c == "$HDD" ]] || die "HDD confirmation failed"
fi

timedatectl set-ntp true

# ---------- pacman config on the live ISO (multilib needed for Steam/Wine) ----------
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
sed -i 's/^#Color/Color/; s/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
echo ">> Ranking mirrors..."
reflector --country Singapore,Indonesia,Japan,Malaysia --protocol https --latest 20 --sort rate \
  --save /etc/pacman.d/mirrorlist 2>/dev/null || echo "reflector failed, using default mirrors"
pacman -Sy --noconfirm archlinux-keyring

# ---------- partitioning ----------
sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1GiB -t1:ef00 -c1:EFI -n2:0:0 -t2:8300 -c2:root "$DISK"
partprobe "$DISK"; sleep 2
EFI=$(part "$DISK" 1); ROOT=$(part "$DISK" 2)
mkfs.fat -F32 -n EFI "$EFI"
mkfs.ext4 -F -L arch "$ROOT"
mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot

if [[ -n $HDD ]]; then
  wipefs -a "$HDD"
  sgdisk --zap-all "$HDD"
  sgdisk -n1:0:0 -t1:8300 -c1:storage "$HDD"
  partprobe "$HDD"; sleep 2
  HDDP=$(part "$HDD" 1)
  mkfs.ext4 -F -L storage "$HDDP"
  mount --mkdir "$HDDP" /mnt/mnt/storage
fi

# ---------- package list ----------
PKGS=(
  # base system
  base base-devel linux linux-headers linux-firmware amd-ucode sof-firmware
  e2fsprogs dosfstools ntfs-3g exfatprogs sudo nano vim git wget curl unzip p7zip
  man-db bash-completion reflector zram-generator htop btop fastfetch
  networkmanager bluez bluez-utils
  # KDE Plasma
  plasma-meta sddm sddm-kcm xorg-xwayland xdg-desktop-portal-kde
  konsole dolphin kate ark spectacle gwenview okular partitionmanager kdeconnect
  firefox
  # fonts
  ttf-liberation ttf-dejavu noto-fonts noto-fonts-cjk noto-fonts-emoji
  # audio (PipeWire)
  pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber alsa-utils pavucontrol
  lib32-pipewire lib32-pipewire-jack
  # GPU: AMD RDNA1 (RX 5700 XT) - open source Mesa/RADV
  mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
  vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils
  libva-mesa-driver lib32-libva-mesa-driver mesa-vdpau lib32-mesa-vdpau libva-utils
  radeontop lact
  # multimedia / codecs
  ffmpeg gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
  vlc vlc-plugins-all mpv
  # gaming
  steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope goverlay
  wine-staging winetricks wine-mono wine-gecko lutris protontricks
  lib32-gnutls lib32-openal lib32-libpulse lib32-alsa-plugins
  # streaming / recording
  obs-studio v4l2loopback-dkms v4l2loopback-utils kdenlive
)

# keep only packages that exist in the repos (renamed/removed packages won't abort the install)
AVAILABLE=(); MISSING=()
for p in "${PKGS[@]}"; do
  if pacman -Si "$p" >/dev/null 2>&1; then AVAILABLE+=("$p"); else MISSING+=("$p"); fi
done
((${#MISSING[@]})) && echo ">> Skipping packages not found in repos: ${MISSING[*]}"

echo ">> Installing system (this takes a while)..."
pacstrap -K /mnt "${AVAILABLE[@]}"

genfstab -U /mnt >> /mnt/etc/fstab
sed -i '/\/mnt\/storage/ s/relatime/relatime,nofail/' /mnt/etc/fstab
cp /etc/pacman.conf /mnt/etc/pacman.conf
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

# ---------- configuration inside the new system ----------
cat > /mnt/root/setup-chroot.sh <<'CHROOT'
set -euo pipefail

ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/; s/^#id_ID.UTF-8 UTF-8/id_ID.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "$HOST" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOST.localdomain $HOST
EOF

# user
useradd -m -G wheel,video,audio,input,storage -s /bin/bash "$USERNAME" || useradd -m -G wheel,video,audio,input -s /bin/bash "$USERNAME"
getent group gamemode >/dev/null && usermod -aG gamemode "$USERNAME" || true
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
[[ -d /mnt/storage ]] && chown "$USERNAME:$USERNAME" /mnt/storage || true

# early KMS for amdgpu
sed -i 's/^MODULES=()/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
mkinitcpio -P

# bootloader: systemd-boot
bootctl install
cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF
cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=UUID=$ROOT_UUID rw quiet amdgpu.ppfeaturemask=0xffffffff
EOF
cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux-fallback.img
options root=UUID=$ROOT_UUID rw
EOF

# zram swap (16GB RAM -> 8GB zram)
cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF

# gaming sysctl
cat > /etc/sysctl.d/99-gaming.conf <<EOF
vm.swappiness = 100
vm.max_map_count = 2147483642
vm.vfs_cache_pressure = 50
EOF

# OBS virtual camera
echo v4l2loopback > /etc/modules-load.d/v4l2loopback.conf
echo 'options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1' > /etc/modprobe.d/v4l2loopback.conf

# SDDM: Wayland greeter is optional; default KDE session is fine
systemctl enable NetworkManager sddm bluetooth fstrim.timer systemd-timesyncd systemd-boot-update.service reflector.timer
CHROOT

ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
arch-chroot /mnt env HOST="$HOST" USERNAME="$USERNAME" TIMEZONE="$TIMEZONE" KEYMAP="$KEYMAP" \
  ROOT_UUID="$ROOT_UUID" bash /root/setup-chroot.sh
rm /mnt/root/setup-chroot.sh

# copy stage 2 next to this script into the user's home, if available
SRC="$(dirname "$(readlink -f "$0")")/02-post-install.sh"
[[ -f $SRC ]] && install -m 755 -o 1000 -g 1000 "$SRC" "/mnt/home/$USERNAME/02-post-install.sh" || true

echo
echo ">> Set passwords:"
arch-chroot /mnt passwd root
arch-chroot /mnt passwd "$USERNAME"

echo
echo "Done. Run: umount -R /mnt && reboot"
echo "After logging in to KDE, open Konsole and run: ~/02-post-install.sh"
