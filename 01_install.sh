#!/bin/bash
set -e

# Target Disks
NVME="/dev/nvme0n1"
HDD_PART="/dev/sda1"

echo "=== Input System Configuration ==="
read -p "Set Hostname [default: archlinux]: " INPUT_HOSTNAME
HOSTNAME=${INPUT_HOSTNAME:-archlinux}

read -p "Set Username [default: famouzak]: " INPUT_USERNAME
USERNAME=${INPUT_USERNAME:-famouzak}

echo "----------------------------------------"
echo " Hostname : $HOSTNAME"
echo " Username : $USERNAME"
echo "----------------------------------------"

echo "=== 1. Sync Clock & Update Mirrorlist ==="
timedatectl set-ntp true
# [FIX] -Syu instead of -Sy untuk hindari partial upgrade
pacman -Syu --noconfirm reflector
echo "Searching for the fastest mirror ..."
reflector --country Indonesia,Singapore --protocol https --latest 15 --download-timeout 5 --sort rate --save /etc/pacman.d/mirrorlist

echo "=== 2. Partitioning NVMe ($NVME) ==="
sgdisk --zap-all $NVME
parted -s $NVME mklabel gpt
parted -s $NVME mkpart ESP fat32 1MiB 1024MiB             # 1 GB EFI
parted -s $NVME set 1 esp on
parted -s $NVME mkpart primary linux-swap 1024MiB 5120MiB # 4 GB Swap
parted -s $NVME mkpart primary btrfs 5120MiB 100%         # Sisa ~251 GB Btrfs

BOOT_PART="${NVME}p1"
SWAP_PART="${NVME}p2"
ROOT_PART="${NVME}p3"

echo "=== 3. Formatting NVMe Partitions ==="
mkfs.fat -F32 -n "EFI" $BOOT_PART
mkswap -L "ARCH_SWAP" $SWAP_PART
swapon $SWAP_PART
mkfs.btrfs -f -L "ARCH_LINUX" $ROOT_PART

echo "=== 4. Creating Btrfs Subvolumes ==="
mount $ROOT_PART /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "=== 5. Mounting Subvolumes ==="
BTRFS_OPTS="noatime,compress=zstd:1,ssd,discard=async,space_cache=v2"

mount -o $BTRFS_OPTS,subvol=@ $ROOT_PART /mnt
mkdir -p /mnt/{boot/efi,home,.snapshots,var/log,var/cache/pacman/pkg,mnt/wdblue}

mount -o $BTRFS_OPTS,subvol=@home $ROOT_PART /mnt/home
mount -o $BTRFS_OPTS,subvol=@snapshots $ROOT_PART /mnt/.snapshots
mount -o $BTRFS_OPTS,subvol=@var_log $ROOT_PART /mnt/var/log
mount -o $BTRFS_OPTS,subvol=@pkg $ROOT_PART /mnt/var/cache/pacman/pkg
mount $BOOT_PART /mnt/boot/efi

echo "=== 6. Mounting HDD WD BLUE ==="
mount $HDD_PART /mnt/mnt/wdblue

echo "=== 7. Installing Base System ==="
pacstrap -K /mnt \
  base base-devel \
  linux linux-headers \
  linux-lts linux-lts-headers \
  linux-zen linux-zen-headers \
  linux-firmware amd-ucode \
  btrfs-progs neovim nano git networkmanager sudo reflector

echo "=== 8. Generating FSTAB (Mount NVMe & HDD) ==="
genfstab -U /mnt >> /mnt/etc/fstab

if grep -q "/mnt/wdblue" /mnt/etc/fstab; then
  sed -i '/\/mnt\/wdblue/ s/defaults/defaults,nofail/' /mnt/etc/fstab
  echo ">>> HDD mounted with 'nofail' option"
fi

echo "=== 9. Setting Up Environment for Chroot ==="
# Save variabel to read by 02_chroot.sh
cat <<EOF > /mnt/root/install_vars.sh
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
EOF

# Copy All Scrypts Folder to /mnt/root/scripts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p /mnt/root/scripts
cp -r "$SCRIPT_DIR"/* /mnt/root/scripts/
chmod +x /mnt/root/scripts/*.sh

echo "=== Base Install is Finished! Continuing to Step 02 (Chroot)... ==="
arch-chroot /mnt /bin/bash /root/scripts/02_chroot.sh