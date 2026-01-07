# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  coreutils,
  util-linux,
  hwinfo,
  ncurses,
  writeShellApplication,
  zstd,
  cryptsetup,
  gptfdisk,
  parted,
  e2fsprogs,
  btrfs-progs,
  dosfstools,
  rsync,
}:
writeShellApplication {
  name = "ghaf-installer";
  runtimeInputs = [
    coreutils
    util-linux
    zstd
    hwinfo
    ncurses # Needed for `clear` command
    cryptsetup # LUKS encryption operations
    gptfdisk # sgdisk for GPT partitioning
    parted # Partition management
    e2fsprogs # ext4 filesystem tools
    btrfs-progs # btrfs filesystem tools
    dosfstools # vfat/FAT filesystem tools
    rsync # Efficient file copying
  ];
  text = builtins.readFile ./ghaf-installer.sh;
  meta = {
    description = "Installer script for the Ghaf project";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
