#!/bin/bash
set -e

# Target storage devices
NVME="/dev/nvme0n1"
HDD_PART="/dev/sda1"

echo "=== System Configuration Input ==="
read -p "Enter Hostname [default: archlinux]: " INPUT_HOSTNAME
HOSTNAME=${INPUT_HOSTNAME:-archlinux}

read -p "Enter Username [default: famouzak]: " INPUT_USERNAME
USERNAME=${INPUT_USERNAME:-famouzak}

echo "----------------------------------------"
echo " Hostname : $HOSTNAME"
echo " Username : $USERNAME"
echo "----------------------------------------"

echo "=== 1. Sync Network Time & Optimize Mirrorlist ==="
timedatectl set-ntp true

echo "Evaluating fastest mirrors (Indonesia & Singapore)..."
reflector --country Indonesia,Singapore --protocol https --latest 15 --download-timeout 5 --sort rate --save /etc/pacman.d/mirrorlist

echo "=== 2. Partitioning NVMe Drive ($NVME) ==="
sgdisk --zap-all $NVME
parted -s $NVME mklabel gpt
parted -s $NVME mkpart ESP fat32 1MiB 1024MiB       # 1 GiB ESP / Boot
parted -s $NVME set 1 esp on
parted -s $NVME mkpart primary linux-swap 1024MiB 5120MiB # 4 GiB Swap space
parted -s $NVME mkpart primary btrfs 5120MiB 100%   # Remaining capacity for Btrfs root

BOOT_PART="${NVME}p1"
SWAP_PART="${NVME}p2"
ROOT_PART="${NVME}p3"

echo "=== 3. Formatting NVMe Partitions ==="
mkfs.fat -F32 -n "EFI" $BOOT_PART
mkswap -L "ARCH_SWAP" $SWAP_PART
swapon $SWAP_PART
mkfs.btrfs -f -L "ARCH_LINUX" $ROOT_PART

echo "=== 4. Provisioning Btrfs Subvolumes ==="
mount $ROOT_PART /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "=== 5. Mounting Btrfs Subvolumes ==="
BTRFS_OPTS="noatime,compress=zstd:1,ssd,discard=async,space_cache=v2"

mount -o $BTRFS_OPTS,subvol=@ $ROOT_PART /mnt
mkdir -p /mnt/{boot/efi,home,.snapshots,var/log,var/cache/pacman/pkg,mnt/wdblue}

mount -o $BTRFS_OPTS,subvol=@home $ROOT_PART /mnt/home
mount -o $BTRFS_OPTS,subvol=@snapshots $ROOT_PART /mnt/.snapshots
mount -o $BTRFS_OPTS,subvol=@var_log $ROOT_PART /mnt/var/log
mount -o $BTRFS_OPTS,subvol=@pkg $ROOT_PART /mnt/var/cache/pacman/pkg
mount $BOOT_PART /mnt/boot/efi

echo "=== 6. Mounting Secondary Storage  ==="
mount $HDD_PART /mnt/mnt/wdblue

echo "=== 7. Bootstrapping Base System & Kernels ==="
pacstrap -K /mnt \
  base base-devel \
  linux linux-headers \
  linux-lts linux-lts-headers \
  linux-zen linux-zen-headers \
  linux-firmware amd-ucode \
  btrfs-progs neovim git nano pacman networkmanager sudo reflector

echo "=== 8. Generating FSTAB Table ==="
genfstab -U /mnt >> /mnt/etc/fstab

echo "=== 9. Preparing Chroot Environment ==="
# Persist configuration variables for chroot execution
cat <<EOF > /mnt/root/install_vars.sh
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
EOF

# Transfer deployment scripts into chroot environment
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
mkdir -p /mnt/root/scripts
cp -r "$SCRIPT_DIR"/* /mnt/root/scripts/
chmod +x /mnt/root/scripts/*.sh

echo "=== Base installation complete. Transitioning to Step 02 (Chroot)... ==="
arch-chroot /mnt /bin/bash /root/scripts/02_chroot.sh
