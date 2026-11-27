#!/usr/bin/env bash
#
# NixOS install for the EXO Wings K1322 (2-in-1, Intel Bay Trail Z3735F, 2 GB RAM, eMMC storage).
# Run it from the NixOS installer USB, with network.
#
# Before running it:
# - The firmware is most likely 32-bit UEFI (D-64). The stock NixOS installer USB only has the
#   64-bit EFI loader and may not boot on the EXO: see docs/area3-implementacion/fase7-host.md (A3-78).
# - Turn Secure Boot off in the firmware setup (Limine is not signed).
# - Have the flake repository ready: the script shows a deploy key to add to it on GitHub.
# - This script ERASES the chosen disk, Windows included.
#
# Changes from install-gpt-pc.sh: automatic disk detection, eMMC/NVMe partition names (mmcblk0p1), confirmation before
# erasing, the disk erased (only free space) before partitioning, other disks (the microSD), if confirmed, erased and
# left as an empty ext4 disk for files, UEFI check, and the system installed straight from the flake repository
# (nixos-install --flake): the script creates the deploy key, checks the repository before erasing anything and only
# sets the root password. Everything else (users, bootloader, firmware, 'update') comes from the flake.
# If a run stops with an error, running the script again continues the installation: it keeps the partitions of the
# earlier run (unless ERASE is typed), formats only what was not formatted yet and runs nixos-install again, which
# reuses everything already downloaded or built. The deploy key is reused too, in the same live session.

# Clean the terminal before proceeding with user setup
clear

# SUDO
sudo -i

# Stop with an error message (without powering off), also when the script comes through a pipe
fail() {
  echo "ERROR: $1"
  [ -t 0 ] || cat > /dev/null
  exit 1
}

cancel() {
  echo "Cancelled: nothing was changed."
  # When the script comes through a pipe, drain the rest so it does not keep running after this exit
  [ -t 0 ] || cat > /dev/null
  exit 1
}

# Ask everything first, before touching the disk
# Ask for a password twice (visible, by the user's choice) until both match and it is not empty. $1 = variable, $2 = whose
ask_password() {
  local first second
  while true; do
    read -rp "Type the password for $2: " first < /dev/tty
    read -rp "Type it again: " second < /dev/tty
    [ -n "$first" ] && [ "$first" = "$second" ] && break
    echo "Empty or different passwords: try again."
  done
  printf -v "$1" "%s" "$first"
}

# Clean the terminal before proceeding with user setup
#clear

# setting password for user 'root'. It is the only password the script sets: the other users and their passwords
# come from the flake (mutable users).
echo ""
ask_password passwordRoot root
echo ""
echo "Password for root is saved!"
echo ""

echo "Now set the Nix Profile name..."
echo ""
echo "ATTENTION! It must match the name of the configuration in the flake.nix of your repo (nixosConfigurations.<name>)."
echo "The default is 'nixos'."
read -rp "Type Nix Profile name: " nixProfile < /dev/tty
nixProfile=${nixProfile:-nixos} # Use 'nixos' if left empty
echo ""

# Deploy key for the flake repository (what 'connect-repo' did after the first boot). It is created on this live
# system, which clones the repository during the installation, and copied to the new system at the end so 'update'
# keeps working. If the script runs again in the same live session, it reuses the key already added on GitHub.
mkdir -p /root/.ssh
chmod 700 /root/.ssh
printf '%s\n' "Host github.com" "  HostName github.com" "  User git" "  IdentityFile /root/.ssh/github_deploy_key" \
  "  IdentitiesOnly yes" "  StrictHostKeyChecking accept-new" > /root/.ssh/config
[ -f /root/.ssh/github_deploy_key ] || ssh-keygen -t ed25519 -f /root/.ssh/github_deploy_key -N "" < /dev/null > /dev/null
echo "Add this key to your GitHub repository as a deploy key (Settings > Deploy keys, read access is enough):"
echo ""
cat /root/.ssh/github_deploy_key.pub
echo ""

# Repository and branch, checked now with the deploy key: a wrong URL, branch or key shows up before erasing anything
while true; do
  read -rp "SSH URL of the repository (e.g. git@github.com:user/repo.git), or press Enter to cancel: " repoUrl < /dev/tty
  [ -n "$repoUrl" ] || cancel
  if ! [[ $repoUrl =~ ^[^@/:]+@[^@/:]+:[^:]+$ ]]; then
    echo "Use the SSH URL of the repository, like git@github.com:user/repo.git (not the https one)."
    continue
  fi
  read -rp "Branch (press Enter for the default branch of the repository): " branch < /dev/tty
  ref="HEAD"
  [ -n "$branch" ] && ref="refs/heads/$branch"
  git ls-remote --exit-code "$repoUrl" "$ref" < /dev/null > /dev/null && break
  echo "Could not read ${branch:+the branch '$branch' of }$repoUrl: check the URL, the branch and that the deploy key was added on GitHub, then try again."
  echo ""
done
# git@github.com:user/repo.git -> git@github.com/user/repo.git (the format 'update' reads from /root/.github_repo_url)
repoPath=$(tr ':' '/' <<< "$repoUrl")
echo "Repository found: $repoPath${branch:+ (branch $branch)}"
echo ""

echo "Everything is set!"

# Detect the disk to install on, without asking: the internal disk. Never the installer USB (mounted
# at /iso), removable media, USB disks, SD cards (mmc type "SD"; the eMMC is "MMC") or the eMMC boot/rpmb areas.
# On the EXO Wings it is the eMMC (mmcblk0 or mmcblk1).
isoDisk=""
isoSource="$(findmnt -nvo SOURCE /iso 2>/dev/null)"
if [ -n "$isoSource" ]; then
  isoDisk="$(lsblk -ndo PKNAME "$isoSource" 2>/dev/null)"
  # The ISO is usually mounted from the whole USB device, which has no parent: use its own name
  [ -n "$isoDisk" ] || isoDisk="$(lsblk -ndo NAME "$isoSource" 2>/dev/null)"
fi
candidates=()
emmc=()
for d in /sys/block/*; do
  n="${d##*/}"
  case "$n" in loop*|ram*|zram*|sr*|fd*|dm-*|md*|mmcblk*boot*|mmcblk*rpmb) continue ;; esac
  [ "$n" = "$isoDisk" ] && continue
  [ "$(cat "$d/removable" 2>/dev/null)" = "1" ] && continue
  [ "$(lsblk -ndo TRAN "/dev/$n" 2>/dev/null)" = "usb" ] && continue
  [ "$(cat "$d/size" 2>/dev/null || echo 0)" -gt 0 ] || continue
  if [[ $n == mmcblk* ]]; then
    [ "$(cat "$d/device/type" 2>/dev/null)" = "MMC" ] || continue
    emmc+=("$n")
  fi
  candidates+=("$n")
done
if [ "${#emmc[@]}" -eq 1 ]; then
  diskName="${emmc[0]}"
elif [ "${#candidates[@]}" -eq 1 ]; then
  diskName="${candidates[0]}"
else
  # Only when it cannot decide (no disk or several): show the disks and ask
  echo "Could not choose the disk automatically (candidates: ${candidates[*]:-none})."
  lsblk -d -o NAME,SIZE,TYPE,RM,TRAN,MODEL
  read -rp "Disk name (e.g. 'mmcblk0', 'nvme0n1' or 'sda'): " diskName < /dev/tty
fi
echo "Disk to install on: /dev/$diskName"

# The EXO boots with UEFI (32-bit, D-64). Warn if this live system did not boot in UEFI mode.
if [ -d /sys/firmware/efi ]; then
  echo "Firmware: UEFI, $(cat /sys/firmware/efi/fw_platform_size 2>/dev/null || echo '?') bits"
else
  echo "WARNING: this live system did not boot in UEFI mode (BIOS/legacy). The EXO Wings needs UEFI."
fi

# What a disk is, or why it was not chosen, for the lists below
disk_note() {
  local note="discarded" c
  case "$1" in mmcblk*boot*|mmcblk*rpmb) note="eMMC boot area" ;; zram*|ram*) note="RAM disk" ;; sr*) note="CD/DVD" ;; esac
  [ "$(cat "/sys/block/$1/removable" 2>/dev/null)" = "1" ] && note="removable"
  [ "$(lsblk -ndo TRAN "/dev/$1" 2>/dev/null)" = "usb" ] && note="USB disk"
  [[ $1 == mmcblk* ]] && [ "$(cat "/sys/block/$1/device/type" 2>/dev/null)" = "SD" ] && note="SD card"
  [ "$1" = "$isoDisk" ] && note="installer USB"
  for c in "${candidates[@]}"; do [ "$c" = "$1" ] && note="candidate"; done
  echo "$note"
}

# Last chance: show every disk found and the one chosen, with its current partitions, before erasing
# it (Windows included). If the user does not confirm, they can pick another disk from the list.
show_disks() {
  echo ""
  echo "Disks found (>> = the chosen one):"
  while read -r name rest; do
    if [ "$name" = "$diskName" ] && has_install_layout "$name"; then
      printf '>> %-12s %s   <-- CHOSEN: has the partitions of an earlier run\n' "$name" "$rest"
    elif [ "$name" = "$diskName" ]; then
      printf '>> %-12s %s   <-- CHOSEN: WILL BE ERASED\n' "$name" "$rest"
    else
      printf '   %-12s %s   (%s)\n' "$name" "$rest" "$(disk_note "$name")"
    fi
  done < <(lsblk -dn -e 7 -o NAME,SIZE,TYPE,TRAN,MODEL)
  echo ""
  echo "Current partitions of /dev/$diskName:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "/dev/$diskName"
  echo ""
}

# A disk from the list that can be installed on: not the installer USB, the eMMC boot areas,
# RAM disks or CD/DVD drives. USB disks and SD cards are allowed when the user picks them.
installable() {
  [ -n "$1" ] && [ -b "/dev/$1" ] || return 1
  lsblk -dn -e 7 -o NAME | grep -qx -- "$1" || return 1
  [ "$1" = "$isoDisk" ] && return 1
  case "$1" in mmcblk*boot*|mmcblk*rpmb|zram*|ram*|sr*) return 1 ;; esac
  return 0
}

# True when a disk already has exactly the 4 partitions this script creates (GPT, named root, swap, ESP and BIOS, in
# that order): an earlier run partitioned it and stopped, so the installation can continue on it without erasing it.
# A disk that comes with Windows (or anything else) never matches.
has_install_layout() {
  local p="/dev/$1" i=0 name
  [[ $1 =~ [0-9]$ ]] && p="${p}p"
  [ "$(lsblk -ndo PTTYPE "/dev/$1" 2>/dev/null)" = "gpt" ] || return 1
  [ "$(lsblk -lno TYPE "/dev/$1" 2>/dev/null | grep -cx part)" -eq 4 ] || return 1
  for name in root swap ESP BIOS; do
    i=$((i + 1))
    [ "$(lsblk -ndo PARTLABEL "$p$i" 2>/dev/null)" = "$name" ] || return 1
  done
}

installable "$diskName" || { echo "Disk /dev/$diskName cannot be used."; cancel; }
resume=0 # 1 = continue the installation of an earlier run on the partitions it left
while true; do
  show_disks
  if has_install_layout "$diskName"; then
    echo "/dev/$diskName already has the partitions of an earlier run of this script. The installation can continue on"
    echo "them: nothing is erased, only what is not formatted yet gets formatted, and nixos-install reuses what it already did."
    read -rp "Type YES to continue the earlier installation, ERASE to erase /dev/$diskName and start over, or press Enter to choose another disk: " confirm < /dev/tty
    [ "$confirm" = "YES" ] && { resume=1; break; }
    [ "$confirm" = "ERASE" ] && break
  else
    read -rp "This will ERASE /dev/$diskName. Type YES to continue, or press Enter to choose another disk: " confirm < /dev/tty
    [ "$confirm" = "YES" ] && break
  fi
  read -rp "Disk to use instead (a name from the list), or press Enter to cancel: " other < /dev/tty
  [ -n "$other" ] || cancel
  if installable "$other"; then
    diskName="$other"
  else
    echo "'$other' cannot be used: pick a disk from the list (not the installer USB, eMMC boot areas, RAM disks or CD/DVD)."
  fi
done

# Other disks of this machine that can also be erased and left as an empty ext4 disk for the user's files (on the
# EXO Wings, the microSD card in its slot, which shows up as another mmcblk disk). NixOS is not installed on them and
# does not mount them: they are free space for files after the installation. Asked now, before erasing anything;
# Enter keeps each one as it is. The installer USB, other USB disks, the eMMC boot areas, RAM disks and CD/DVD
# drives are never offered.
alsoErase=()
for name in $(lsblk -dn -e 7 -o NAME); do
  [ "$name" = "$diskName" ] && continue
  installable "$name" || continue
  [ "$(lsblk -ndo TRAN "/dev/$name" 2>/dev/null)" = "usb" ] && continue
  echo ""
  echo "Another disk: /dev/$name ($(disk_note "$name")). Its current partitions:"
  lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "/dev/$name"
  read -rp "Also ERASE /dev/$name and leave it as an empty disk for your files (ext4, NixOS is not installed on it)? Type YES to erase it, or press Enter to keep it: " confirm < /dev/tty
  [ "$confirm" = "YES" ] && alsoErase+=("$name")
done

# Partitions of a disk (/dev/sda1, /dev/mmcblk1p1, ...): only them, not the disk or what sits on top (LVM, encryption)
partitions_of() {
  lsblk -lnpo NAME,TYPE "/dev/$1" | awk '$2 == "part" { print $1 }'
}

# Stop using a disk before erasing it: turn off its swap and unmount its partitions (an earlier run of this
# script leaves them mounted on /mnt, with the swap on). If something still uses it (LVM, RAID, encryption, a busy
# mount), stop before erasing anything.
release_disk() {
  local p
  for p in $(partitions_of "$1"); do
    swapoff "$p" 2>/dev/null
    umount -A "$p" 2>/dev/null
  done
  if lsblk -rno TYPE,MOUNTPOINTS "/dev/$1" | grep -qvE '^(disk|part) *$'; then
    lsblk -o NAME,TYPE,MOUNTPOINTS "/dev/$1"
    fail "/dev/$1 is still in use (mounted, swap, LVM, RAID or encryption). Free it and run the script again: nothing was erased."
  fi
}

# Leave a disk with only free space, like deleting all its partitions with cfdisk: erase the signatures inside
# each partition (filesystems, old swap, RAID/LVM) and then the partition tables of the disk (MBR, GPT and the
# GPT backup at the end). Only this disk: the eMMC boot areas (mmcblk1boot0/boot1) are other devices and stay as they are.
wipe_disk() {
  local p
  echo ""
  echo "Erasing /dev/$1..."
  for p in $(partitions_of "$1"); do
    wipefs -af "$p"
  done
  udevadm settle # let udev finish reading the wiped partitions
  # Without -f, wipefs opens the disk exclusively (it fails if something still uses it) and, after erasing,
  # makes the kernel re-read the now empty partition table, so the old partitions disappear
  wipefs -a "/dev/$1" || fail "Could not erase the partition table of /dev/$1."
  udevadm settle # wait until the old partitions are gone before creating the new ones
}

# Leave an erased extra disk as one empty ext4 partition for files, labeled 'microSD' (SD cards) or 'Archivos' (other
# disks). Its root directory belongs to the group 'users' (GID 100 on NixOS, the group of every normal user) and the
# group can write on it (2775: new folders keep the group), so the users created by the flake can save files without
# sudo once it is mounted. Nothing mounts it: it is not in the NixOS configuration.
files_disk() {
  local p="/dev/$1" label="Archivos" dir
  [[ $1 =~ [0-9]$ ]] && p="${p}p"
  [ "$(disk_note "$1")" = "SD card" ] && label="microSD"
  echo ""
  echo "Preparing /dev/$1 for files (ext4, label '$label')..."
  parted -s "/dev/$1" -- mklabel msdos || return 1
  parted -s "/dev/$1" -- mkpart primary ext4 1MiB 100% || return 1
  udevadm settle
  mkfs.ext4 -F -L "$label" -E root_owner=0:100 "${p}1" || return 1
  # mkfs.ext4 cannot set the mode of the root directory: mount it for a moment to do it
  dir="$(mktemp -d)"
  mount "${p}1" "$dir" || return 1
  chmod 2775 "$dir"
  umount "$dir"
  rmdir "$dir"
}

# Stop using the disks (an earlier run leaves them mounted on /mnt, with the swap on) and erase them, so they are
# empty (only free space) when they get partitioned. When continuing an earlier run, the install disk is not erased.
installSwap=/mnt/.install-swap # temporary swap file for nixos-install (see below), active if an earlier run stopped
swapoff "$installSwap" 2>/dev/null
umount -R /mnt 2>/dev/null # free /mnt if an earlier run of this script left the new system mounted there
for name in "${alsoErase[@]}" "$diskName"; do release_disk "$name"; done
eraseDisks=("${alsoErase[@]}")
[ "$resume" = 1 ] || eraseDisks+=("$diskName")
for name in "${eraseDisks[@]}"; do wipe_disk "$name"; done
# The extra disks (the microSD on the EXO) are ready for files right away
for name in "${alsoErase[@]}"; do
  files_disk "$name" || fail "Could not prepare /dev/$name for files (NixOS was not installed yet)."
done

# Partition names: disks whose name ends in a digit (eMMC, NVMe) add a 'p' (mmcblk0 -> mmcblk0p1); sda -> sda1
part="/dev/$diskName"
[[ $diskName =~ [0-9]$ ]] && part="${part}p"

if [ "$resume" = 1 ]; then
  echo ""
  echo "Continuing the earlier installation: the partitions of /dev/$diskName are kept."
else
  partFail="Could not create the partitions of /dev/$diskName. Run the script again."

  # create gpt partition table
  parted -s /dev/$diskName -- mklabel gpt || fail "$partFail"

  # Add the root partition. This will fill the disk except for the end part, where the swap will live.
  # It starts at 1024MiB, right where the BIOS boot partition ends (with 1024MB = 976.6MiB they would overlap).
  parted -s /dev/$diskName -- mkpart root ext4 1024MiB -2GB || fail "$partFail"

  # Next, add a swap partition. The size required will vary according to needs, here a 2 GB one is created (the EXO has 2 GB of RAM; swap also helps nix evaluate the flake).
  parted -s /dev/$diskName -- mkpart swap linux-swap -2GB 100% || fail "$partFail"

  # Finally, the boot partition. NixOS by default uses the ESP (EFI system partition) as its /boot partition. It takes the first half of the space reserved at the start of the disk (1MB to 512MB; the BIOS boot partition below takes 512MiB to 1024MiB). On the EXO, the 32-bit UEFI firmware starts Limine from EFI/BOOT/BOOTIA32.EFI on this partition (D-64).
  parted -s /dev/$diskName -- mkpart ESP fat32 1MB 512MB || fail "$partFail"
  parted -s /dev/$diskName -- set 3 esp on || fail "$partFail"

  # BIOS boot partition: the EXO does not use it (UEFI only); it stays for PCs with BIOS, like nixos-ferchu's biosSupport = true
  parted -s /dev/$diskName -- mkpart BIOS 512MiB 1024MiB || fail "$partFail"
  parted -s /dev/$diskName -- set 4 bios_grub on || fail "$partFail"
fi

# parted returns before udev is done with the new partition table: each time parted closes the disk, udev reads it
# again and the partitions (/dev/mmcblk1p1, ...) can disappear for a moment. Wait until udev is done and the 4
# partitions are there; formatting right away left root without a filesystem once on the EXO (P13).
udevadm settle
for i in 1 2 3 4; do
  for _ in $(seq 20); do [ -b "$part$i" ] && break; sleep 0.5; done
  [ -b "$part$i" ] || fail "The partition $part$i did not show up after partitioning /dev/$diskName. Run the script again."
done
udevadm settle

#Formatting
# format_part <partition> <filesystem type> <what it is> <command...>: format it. When continuing an earlier run,
# only if it does not have that filesystem yet (the earlier run stopped before formatting it, or formatting failed).
format_part() {
  local dev="$1" type="$2" what="$3"
  shift 3
  if [ "$resume" = 1 ] && [ "$(blkid -p -o value -s TYPE "$dev" 2>/dev/null)" = "$type" ]; then
    echo "$dev ($what) is already formatted ($type) by the earlier run: kept."
    return
  fi
  "$@" "$dev" || fail "Could not format $dev ($what). Run the script again."
}
format_part "${part}1" ext4 root mkfs.ext4 -F -L nixos
format_part "${part}2" swap swap mkswap -L swap
format_part "${part}3" vfat ESP mkfs.fat -F 32 -n boot

# Nothing of the disks is mounted now, so /mnt is just a folder of this live system, in RAM. If an earlier run
# stopped before mounting the disk, it may have written there (the Nix store and caches of the installation), and
# that would take RAM hidden under the mount: delete it.
mountedOnMnt="$(findmnt -rno TARGET,SOURCE | grep -E '^/mnt(/| )')"
if [ -n "$mountedOnMnt" ]; then
  echo "$mountedOnMnt"
  fail "Something is still mounted on /mnt (above). Unmount it and run the script again."
fi
if [ -n "$(ls -A /mnt 2>/dev/null)" ]; then
  echo "Deleting what an earlier run left in /mnt (in the RAM of this live system)..."
  find /mnt -xdev -mindepth 1 -delete || fail "Could not empty /mnt. Reboot the installer USB and run the script again."
fi

# mounting. Stop if something fails: without root mounted on /mnt, the hardware configuration would have no
# fileSystems."/" (nixos-install fails with "fileSystems."/".fsType ... has no value defined") and everything
# would be written to the RAM of this live system.
mount "${part}1" /mnt || fail "Could not mount ${part}1 (root) on /mnt. Run the script again and type ERASE to start over."
mkdir -p /mnt/boot
mount "${part}3" /mnt/boot || fail "Could not mount ${part}3 (ESP) on /mnt/boot. Run the script again and type ERASE to start over."
swapon "${part}2" || fail "Could not turn on the swap ${part}2. Run the script again and type ERASE to start over."

# Hardware configuration of the new system (disks, kernel modules), which the flake imports. Only this file: the
# system itself comes from the flake, so no configuration.nix is written.
mkdir -p /mnt/etc/nixos
nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware-configuration.nix || fail "Could not generate the hardware configuration."
# The flake can import it as <hardware> (the -I of nixos-install below) or as /etc/nixos/hardware-configuration.nix.
# While installing, that absolute path is read on this live system, so a copy goes there too.
mkdir -p /etc/nixos
cp /mnt/etc/nixos/hardware-configuration.nix /etc/nixos/hardware-configuration.nix

# The flake to install: git+ssh://git@github.com/user/repo.git[?ref=branch]#profile (the query goes before the '#')
flake_ref() {
  local ref="git+ssh://$repoPath"
  [ -n "$branch" ] && ref="$ref?ref=$branch"
  echo "$ref#$nixProfile"
}

# Memory for the installation (P14). Evaluating the flake takes more than the 2 GB of RAM of the EXO, and the programs
# of this live system (systemd included) are read from the installer USB (squashfs). Under memory pressure the kernel
# drops their pages and reads them again from the USB, over and over; once those reads failed, systemd crashed and
# the kernel panicked. So, for the rest of this live session:
# - a temporary swap file on the new root, besides the swap partition, so the Nix evaluator has room. It is created
#   after the hardware configuration (which ignores swap files anyway) and deleted after the installation;
# - vm.swappiness=150: above 100 tells the kernel that swapping (to the eMMC) costs less than reading files again
#   (from the USB), so it swaps the memory of the evaluator out instead of dropping the programs of the live system;
# - vm.min_free_kbytes=65536: 64 MiB always free for the USB and disk drivers, which cannot wait for memory.
if ! swapon --show=NAME --noheadings | grep -qx "$installSwap"; then
  rm -f "$installSwap"
  if fallocate -l 4GiB "$installSwap" && chmod 600 "$installSwap" && mkswap "$installSwap" > /dev/null && swapon "$installSwap"; then
    echo "Temporary swap file for the installation: $installSwap (4 GiB, deleted at the end)."
  else
    rm -f "$installSwap"
    echo "WARNING: could not create the temporary swap file: the installation goes on with the swap partition only."
  fi
fi
sysctl -q -w vm.swappiness=150 vm.min_free_kbytes=65536 || echo "WARNING: could not change the memory settings of the kernel."

echo ""
echo "Now installing NixOS from $(flake_ref)..."
echo ""
# Install straight from the flake: the first generation is already the system of the repo, with nothing in between
# to clean up later.
# - XDG_CACHE_HOME: the Nix caches (the clone of the repo, the nixpkgs sources) go to the new disk instead of RAM
#   (this live system runs from RAM and the EXO has 2 GB). Deleted after the installation.
# - DISK: the install disk as a plain name (e.g. mmcblk1), read by the flake with builtins.getEnv "DISK" (needs --impure).
# - --no-channel-copy: do not copy the nixpkgs of the ISO to the new system. --max-jobs 1: one build at a time.
# - --no-root-passwd: nixos-install only asks for it on a terminal, so it is set below with chpasswd.
# If it fails (a wrong profile name, the network), it can be retried here without partitioning again.
until XDG_CACHE_HOME=/mnt/.install-cache DISK="$diskName" nixos-install --flake "$(flake_ref)" --impure \
    -I hardware=/mnt/etc/nixos/hardware-configuration.nix \
    --no-channel-copy --no-root-passwd --max-jobs 1 < /dev/null; do
  echo ""
  echo "nixos-install failed with $(flake_ref): read the error above."
  read -rp "Press Enter to try again, type another Nix profile name to try with it, or type STOP to quit: " answer < /dev/tty
  [ "$answer" = "STOP" ] && fail "nixos-install failed: NixOS was not installed. Run the script again and type YES to continue from here (the partitions are kept)."
  [ -n "$answer" ] && nixProfile="$answer"
done
rm -rf /mnt/.install-cache

# Setting 'root' password. The other users and their passwords come from the flake (mutable users).
echo "root:$passwordRoot" | chpasswd -R /mnt || fail "Could not set the root password (fix it with: nixos-enter --root /mnt, then passwd)."

# Hand the repository over to the new system, so 'update' can rebuild from it: the deploy key, the SSH config for
# github.com (and its host key, already accepted) and the repository URL
mkdir -p /mnt/root/.ssh
chmod 700 /mnt/root /mnt/root/.ssh
cp -p /root/.ssh/config /root/.ssh/github_deploy_key /root/.ssh/github_deploy_key.pub /mnt/root/.ssh/ || fail "Could not copy the deploy key to the new system."
[ -f /root/.ssh/known_hosts ] && cp -p /root/.ssh/known_hosts /mnt/root/.ssh/
echo "$repoPath" > /mnt/root/.github_repo_url

# Delete from the new system what the installation left and nothing uses (sources, compilers and other build
# dependencies of what was compiled here). The installed generation stays: the system profile keeps it.
echo ""
echo "Removing what the installation left and the new system does not use..."
nixos-enter --root /mnt -c 'nix-collect-garbage' < /dev/null || echo "WARNING: could not clean the Nix store of the new system. It works anyway: run 'sudo nix-collect-garbage' after booting."
# The temporary swap file is not part of the new system
swapoff "$installSwap" 2>/dev/null
rm -f "$installSwap"
echo ""

# Final messages
echo "Everything's done!"
echo ""
echo "Now shutting down the system..."
echo ""
echo "Don't forget to REMOVE the installation media and then boot the system!"
sleep 5

# shutdown the system after installation
poweroff
