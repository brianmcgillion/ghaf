#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Make sure $IMG_PATH env is set
if [ -z "$IMG_PATH" ]; then
  echo "IMG_PATH is not set!"
  exit
fi

usage() {
  echo " "
  echo "Usage: $(basename "$0") [-w] [-e|--disk-encryption]"
  echo "  -w                 Wipe only"
  echo "  -e, --disk-encryption  Enable LUKS disk encryption for swap and persist partitions"
  exit 1
}

WIPE_ONLY=false
ENCRYPTION_ENABLED=false

# Parse arguments (supports both short and long options)
while [[ $# -gt 0 ]]; do
  case $1 in
  -w)
    WIPE_ONLY=true
    shift
    ;;
  -e | --disk-encryption)
    ENCRYPTION_ENABLED=true
    shift
    ;;
  -*)
    echo "Unknown option: $1"
    usage
    ;;
  *)
    shift
    ;;
  esac
done

# Cleanup function to be called on error or exit
cleanup() {
  echo "Cleaning up..."
  # Unmount filesystems if mounted (reverse order of mounting)
  if mountpoint -q /mnt/persist 2>/dev/null; then
    umount /mnt/persist || true
  fi
  if mountpoint -q /mnt/boot 2>/dev/null; then
    umount /mnt/boot || true
  fi
  if mountpoint -q /mnt 2>/dev/null; then
    umount /mnt || true
  fi
  # Close LUKS devices if open
  if [ -e /dev/mapper/swap ]; then
    cryptsetup close swap || true
  fi
  if [ -e /dev/mapper/persist ]; then
    cryptsetup close persist || true
  fi
}

# Function to create partitions and setup encryption
install_with_encryption() {
  # Set up trap to cleanup on error
  trap cleanup ERR EXIT

  local MOUNT_POINT="/mnt"
  local BOOT_PART=""
  local ESP_PART=""
  local SWAP_PART=""
  local ROOT_PART=""
  local PERSIST_PART=""

  echo "Creating GPT partition table..."
  sgdisk -Z "$DEVICE_NAME" >/dev/null 2>&1 || true
  sgdisk -o "$DEVICE_NAME"

  echo "Creating partitions..."
  # Partition layout matching disko-debug-partition.nix:
  # 1. boot (1M, EF02 - BIOS boot)
  # 2. esp (500M, EF00 - EFI System)
  # 3. swap (12G, encrypted if --disk-encryption)
  # 4. root (75G, ext4) - sized to hold 70GB decompressed image during installation
  # 5. persist (2G or remaining space, encrypted if --disk-encryption)

  sgdisk -n 1:0:+1M -t 1:EF02 -c 1:boot "$DEVICE_NAME"
  sgdisk -n 2:0:+500M -t 2:EF00 -c 2:ESP "$DEVICE_NAME"
  sgdisk -n 3:0:+12G -t 3:8200 -c 3:swap "$DEVICE_NAME"
  sgdisk -n 4:0:+75G -t 4:8300 -c 4:root "$DEVICE_NAME"
  sgdisk -n 5:0:+2G -t 5:8300 -c 5:persist "$DEVICE_NAME"

  # Inform kernel of partition changes
  partprobe "$DEVICE_NAME"
  sleep 2

  # Determine partition naming scheme (nvme vs sd/hd)
  if [[ $DEVICE_NAME =~ nvme ]]; then
    # shellcheck disable=SC2034  # BOOT_PART is intentionally unused (BIOS boot partition)
    BOOT_PART="${DEVICE_NAME}p1"
    ESP_PART="${DEVICE_NAME}p2"
    SWAP_PART="${DEVICE_NAME}p3"
    ROOT_PART="${DEVICE_NAME}p4"
    PERSIST_PART="${DEVICE_NAME}p5"
  else
    # shellcheck disable=SC2034  # BOOT_PART is intentionally unused (BIOS boot partition)
    BOOT_PART="${DEVICE_NAME}1"
    ESP_PART="${DEVICE_NAME}2"
    SWAP_PART="${DEVICE_NAME}3"
    ROOT_PART="${DEVICE_NAME}4"
    PERSIST_PART="${DEVICE_NAME}5"
  fi

  # Close any existing LUKS devices with names we'll use
  # This handles the case where a previous install attempt left devices open
  echo "Checking for existing LUKS devices..."
  if [ -e /dev/mapper/swap ]; then
    echo "Closing existing swap device..."
    cryptsetup close swap 2>/dev/null || true
  fi
  if [ -e /dev/mapper/persist ]; then
    echo "Closing existing persist device..."
    cryptsetup close persist 2>/dev/null || true
  fi

  echo "Setting up encryption for swap partition..."
  # Create LUKS encrypted swap with empty password (matching disko config)
  # Create a temporary empty password file
  PASS_FILE="/tmp/luks-password-$$"
  touch "$PASS_FILE"
  chmod 600 "$PASS_FILE"

  cryptsetup luksFormat --type luks2 --batch-mode --key-file="$PASS_FILE" "$SWAP_PART"
  cryptsetup open --key-file="$PASS_FILE" "$SWAP_PART" swap

  echo "Setting up encryption for persist partition..."
  # Create LUKS encrypted persist with empty password
  cryptsetup luksFormat --type luks2 --batch-mode --key-file="$PASS_FILE" "$PERSIST_PART"
  cryptsetup open --key-file="$PASS_FILE" "$PERSIST_PART" persist

  echo "Creating filesystems..."
  # Format ESP partition as vfat
  mkfs.vfat -F 32 -n ESP "$ESP_PART"

  # Create swap on encrypted device
  mkswap -L swap /dev/mapper/swap

  # Format root as ext4
  mkfs.ext4 -F -L root "$ROOT_PART"

  # Format persist as btrfs on encrypted device
  mkfs.btrfs -f -L persist /dev/mapper/persist

  echo "Mounting filesystems..."
  mkdir -p "$MOUNT_POINT"
  mount "$ROOT_PART" "$MOUNT_POINT"
  mkdir -p "$MOUNT_POINT/boot"
  mount "$ESP_PART" "$MOUNT_POINT/boot"
  mkdir -p "$MOUNT_POINT/persist"
  mount /dev/mapper/persist "$MOUNT_POINT/persist"

  echo "Extracting image to partitions..."
  # Extract the compressed raw image to a temporary location and mount it
  # Use the target disk's root partition for temp storage (has 75GB available)
  # Note: Root partition is sized larger to accommodate the temporary decompressed
  # image during installation. The actual final system uses much less space.
  local TEMP_IMG="$MOUNT_POINT/tmp-ghaf-image.raw"
  local LOOP_DEV=""

  echo "Decompressing image to temporary location..."
  echo "This will take several minutes (decompressing ~6GB to ~70GB)..."
  zstdcat "${raw_file[0]}" >"$TEMP_IMG"

  echo "Mounting image as loop device..."
  LOOP_DEV=$(losetup -fP --show "$TEMP_IMG")

  # Delete the temporary image file immediately after mounting as loop device
  # The loop device keeps the file accessible even after deletion
  # This frees up 70GB of space before we start copying files
  echo "Removing temporary image file (freeing 70GB)..."
  rm -f "$TEMP_IMG"

  # Determine loop partition naming
  local LOOP_ROOT=""
  local LOOP_BOOT=""
  local LOOP_PERSIST=""

  if [[ $LOOP_DEV =~ /dev/loop[0-9]+ ]]; then
    # Try both partition naming schemes
    if [ -e "${LOOP_DEV}p4" ]; then
      LOOP_ROOT="${LOOP_DEV}p4"
      LOOP_BOOT="${LOOP_DEV}p2"
      LOOP_PERSIST="${LOOP_DEV}p5"
    else
      LOOP_ROOT="${LOOP_DEV}4"
      LOOP_BOOT="${LOOP_DEV}2"
      LOOP_PERSIST="${LOOP_DEV}5"
    fi
  fi

  # Mount the image partitions
  mkdir -p /tmp/img_root /tmp/img_boot /tmp/img_persist

  echo "Mounting image root partition..."
  mount -o ro "$LOOP_ROOT" /tmp/img_root

  echo "Mounting image boot partition..."
  mount -o ro "$LOOP_BOOT" /tmp/img_boot

  echo "Mounting image persist partition (may be encrypted)..."
  # Check if persist partition is LUKS encrypted in the image
  if cryptsetup isLuks "$LOOP_PERSIST" 2>/dev/null; then
    cryptsetup open --key-file="$PASS_FILE" "$LOOP_PERSIST" img_persist || {
      # If empty password doesn't work, try without password (for non-encrypted source)
      echo "Note: Source image persist partition appears encrypted but may not be"
      mount -o ro "$LOOP_PERSIST" /tmp/img_persist 2>/dev/null || true
    }
    if [ -e /dev/mapper/img_persist ]; then
      mount -o ro /dev/mapper/img_persist /tmp/img_persist
    fi
  else
    mount -o ro "$LOOP_PERSIST" /tmp/img_persist
  fi

  echo "Copying root filesystem contents..."
  rsync -aAX --info=progress2 /tmp/img_root/ "$MOUNT_POINT/"

  echo "Copying boot filesystem contents..."
  rsync -aAX --info=progress2 /tmp/img_boot/ "$MOUNT_POINT/boot/"

  echo "Copying persist filesystem contents..."
  rsync -aAX --info=progress2 /tmp/img_persist/ "$MOUNT_POINT/persist/"

  echo "Cleaning up temporary mounts..."
  umount /tmp/img_persist || true
  if [ -e /dev/mapper/img_persist ]; then
    cryptsetup close img_persist || true
  fi
  umount /tmp/img_boot || true
  umount /tmp/img_root || true
  losetup -d "$LOOP_DEV" || true
  # Note: $TEMP_IMG was already deleted immediately after loop device creation

  echo "Updating system configuration for encryption..."
  # Update /etc/crypttab if it exists
  if [ -f "$MOUNT_POINT/etc/crypttab" ]; then
    # Add entries for encrypted partitions
    {
      echo "swap UUID=$(blkid -s UUID -o value "$SWAP_PART") none luks,initramfs"
      echo "persist UUID=$(blkid -s UUID -o value "$PERSIST_PART") none luks"
    } >>"$MOUNT_POINT/etc/crypttab"
  fi

  echo "Syncing filesystems..."
  sync

  echo "Unmounting filesystems..."
  umount "$MOUNT_POINT/boot"
  umount "$MOUNT_POINT/persist"
  umount "$MOUNT_POINT"

  echo "Closing encrypted devices..."
  cryptsetup close persist
  cryptsetup close swap

  # Clean up password file
  rm -f "$PASS_FILE"

  # Remove trap
  trap - ERR EXIT

  echo "Encrypted installation complete!"
}

# Fails when TERM=`dumb`.
clear || true

cat <<"EOF"
  ,----..     ,---,
 /   /   \  ,--.' |                 .--.,
|   :     : |  |  :               ,--.'  \
.   |  ;. / :  :  :               |  | /\/
.   ; /--`  :  |  |,--.  ,--.--.  :  : :
;   | ;  __ |  :  '   | /       \ :  | |-,
|   : |.' .'|  |   /' :.--.  .-. ||  : :/|
.   | '_.' :'  :  | | | \__\/: . .|  |  .'
'   ; : \  ||  |  ' | : ," .--.; |'  : '
'   | '/  .'|  :  :_:,'/  /  ,.  ||  | |
|   :    /  |  | ,'   ;  :   .'   \  : \
 \   \ .'   `--''     |  ,     .-./  |,'
  `---`                `--`---'   `--'
EOF

echo "Welcome to Ghaf installer!"

if [ "$ENCRYPTION_ENABLED" = true ]; then
  echo ""
  echo "=============================================="
  echo "WARNING: Disk encryption is ENABLED"
  echo "=============================================="
  echo "The installer will create LUKS encrypted partitions for:"
  echo "  - Swap partition (12GB)"
  echo "  - Persist partition (2GB, expandable)"
  echo ""
  echo "Encryption uses an empty password for automatic unlock."
  echo "=============================================="
  echo ""
fi

echo "To install image or wipe installed image choose path to the device."

hwinfo --disk --short

while true; do
  read -r -p "Device name [e.g. /dev/nvme0n1]: " DEVICE_NAME

  # Input validation: ensure device name starts with /dev/ and contains no path traversal
  if [[ ! $DEVICE_NAME =~ ^/dev/[a-zA-Z0-9._-]+$ ]]; then
    echo "Invalid device name format. Device must be in /dev/ and contain only alphanumeric characters, dots, underscores, and dashes."
    continue
  fi

  # Additional security check: ensure the device exists as a block device
  if [ ! -b "$DEVICE_NAME" ]; then
    echo "Device is not a valid block device!"
    continue
  fi

  # Safely get basename to prevent directory traversal
  device_basename=$(basename "$DEVICE_NAME")
  if [ ! -d "/sys/block/$device_basename" ]; then
    echo "Device not found in sysfs!"
    continue
  fi

  # Check if removable
  if [ "$(cat "/sys/block/$device_basename/removable")" != "0" ]; then
    read -r -p "Device provided is removable, do you want to continue? [y/N] " response
    case "$response" in
    [yY][eE][sS] | [yY])
      break
      ;;
    *)
      continue
      ;;
    esac
  fi

  break
done

echo "Installing/Deleting Ghaf on $DEVICE_NAME"
read -r -p 'Do you want to continue? [y/N] ' response

case "$response" in
[yY][eE][sS] | [yY]) ;;
*)
  echo "Exiting..."
  exit
  ;;
esac

echo "Wiping device..."
# Wipe any possible ZFS leftovers from previous installations
# Set sector size to 512 bytes
SECTOR=512
# 10 MiB in 512-byte sectors
MIB_TO_SECTORS=20480
# Disk size in 512-byte sectors
SECTORS=$(blockdev --getsz "$DEVICE_NAME")
# Wipe first 10MiB of disk
dd if=/dev/zero of="$DEVICE_NAME" bs="$SECTOR" count="$MIB_TO_SECTORS" conv=fsync status=none
# Wipe last 10MiB of disk
dd if=/dev/zero of="$DEVICE_NAME" bs="$SECTOR" count="$MIB_TO_SECTORS" seek="$((SECTORS - MIB_TO_SECTORS))" conv=fsync status=none
echo "Wipe done."

if [ "$WIPE_ONLY" = true ]; then
  echo "Wipe only option selected. Exiting..."
  echo "Please remove the installation media and reboot"
  exit
fi

echo "Installing..."
shopt -s nullglob
raw_file=("$IMG_PATH"/*.raw.zst)

if [ "$ENCRYPTION_ENABLED" = true ]; then
  echo "Disk encryption enabled. Creating encrypted partitions..."
  install_with_encryption
else
  echo "Installing without encryption using standard image write..."
  zstdcat "${raw_file[0]}" | dd of="$DEVICE_NAME" bs=32M status=progress
fi

echo "Installation done. Please remove the installation media and reboot"
