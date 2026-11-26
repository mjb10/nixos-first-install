#!/usr/bin/env bash
#
# NixOS install for the EXO Wings K1322 (2-in-1, Intel Bay Trail Z3735F, 2 GB RAM, eMMC storage).
# Run it from the NixOS installer USB, with network.
#
# Before running it:
# - The firmware is most likely 32-bit UEFI (D-64). The stock NixOS installer USB only has the
#   64-bit EFI loader and may not boot on the EXO: see docs/area3-implementacion/fase7-host.md (A3-78).
# - Turn Secure Boot off in the firmware setup (Limine is not signed).
# - This script ERASES the chosen disk, Windows included.
#
# Changes from install-gpt-pc.sh: automatic disk detection, eMMC/NVMe partition names (mmcblk0p1), confirmation before
# erasing, UEFI check, redistributable firmware (Realtek Wi-Fi), DISK without /dev/ in 'update',
# no docker group or Tailscale, user questions before erasing, and the same stateVersion as nixos-ferchu.

# Clean the terminal before proceeding with user setup
clear

# SUDO
sudo -i

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

# setting password for user 'root'
echo ""
ask_password passwordRoot root
echo ""
echo "Password for root is saved!"

echo ""
# Setting username for new user
echo "Now set the username for the new user"
while true; do
  read -rp "Type username for new user: " username < /dev/tty
  [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]] && [ "$username" != "root" ] && break
  echo "Invalid username: use lowercase letters, digits, '_' or '-', starting with a letter or '_' (not 'root')."
done
echo ""

# Setting password for new user
ask_password password "$username"
echo ""

echo "Now set the Nix Profile name..."
echo ""
echo "ATTENTION! If you are going to connect to a repo it must match with the Nix profile name configured in your flake.nix file you intend to use."
echo "If you are not connecting to a repo, you can choose any name."
echo "The default is 'nixos'."
read -rp "Type Nix Profile name: " nixProfile < /dev/tty
nixProfile=${nixProfile:-nixos} # Use 'nixos' if left empty
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

# Last chance: show every disk found and the one chosen, with its current partitions, before erasing
# it (Windows included). If the user does not confirm, they can pick another disk from the list.
show_disks() {
  echo ""
  echo "Disks found (>> = the one that will be erased):"
  while read -r name rest; do
    note="discarded"
    case "$name" in mmcblk*boot*|mmcblk*rpmb) note="eMMC boot area" ;; zram*|ram*) note="RAM disk" ;; sr*) note="CD/DVD" ;; esac
    [ "$(cat "/sys/block/$name/removable" 2>/dev/null)" = "1" ] && note="removable"
    [ "$(lsblk -ndo TRAN "/dev/$name" 2>/dev/null)" = "usb" ] && note="USB disk"
    [[ $name == mmcblk* ]] && [ "$(cat "/sys/block/$name/device/type" 2>/dev/null)" = "SD" ] && note="SD card"
    [ "$name" = "$isoDisk" ] && note="installer USB"
    for c in "${candidates[@]}"; do [ "$c" = "$name" ] && note="candidate"; done
    if [ "$name" = "$diskName" ]; then
      printf '>> %-12s %s   <-- CHOSEN: WILL BE ERASED\n' "$name" "$rest"
    else
      printf '   %-12s %s   (%s)\n' "$name" "$rest" "$note"
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

installable "$diskName" || { echo "Disk /dev/$diskName cannot be used."; cancel; }
while true; do
  show_disks
  read -rp "This will ERASE /dev/$diskName. Type YES to continue, or press Enter to choose another disk: " confirm < /dev/tty
  [ "$confirm" = "YES" ] && break
  read -rp "Disk to erase instead (a name from the list), or press Enter to cancel: " other < /dev/tty
  [ -n "$other" ] || cancel
  if installable "$other"; then
    diskName="$other"
  else
    echo "'$other' cannot be used: pick a disk from the list (not the installer USB, eMMC boot areas, RAM disks or CD/DVD)."
  fi
done

# Partition names: disks whose name ends in a digit (eMMC, NVMe) add a 'p' (mmcblk0 -> mmcblk0p1); sda -> sda1
part="/dev/$diskName"
[[ $diskName =~ [0-9]$ ]] && part="${part}p"

# create gpt partition table
parted -s /dev/$diskName -- mklabel gpt

# Add the root partition. This will fill the disk except for the end part, where the swap will live.
parted -s /dev/$diskName -- mkpart root ext4 1024MB -2GB

# Next, add a swap partition. The size required will vary according to needs, here a 2 GB one is created (the EXO has 2 GB of RAM; swap also helps nix evaluate the flake).
parted -s /dev/$diskName -- mkpart swap linux-swap -2GB 100%

# Finally, the boot partition. NixOS by default uses the ESP (EFI system partition) as its /boot partition. It uses the space reserved at the start of the disk (about 1 GB). On the EXO, the 32-bit UEFI firmware starts Limine from EFI/BOOT/BOOTIA32.EFI on this partition (D-64).
parted -s /dev/$diskName -- mkpart ESP fat32 1MB 512MB
parted -s /dev/$diskName -- set 3 esp on

# BIOS boot partition: the EXO does not use it (UEFI only); it stays for PCs with BIOS, like nixos-ferchu's biosSupport = true
parted -s /dev/$diskName -- mkpart BIOS 512MiB 1024MiB
parted -s /dev/$diskName -- set 4 bios_grub on

#Formatting
mkfs.ext4 -F -L nixos "${part}1"
mkswap -L swap "${part}2"
mkfs.fat -F 32 -n boot "${part}3"

# mounting
mount "${part}1" /mnt
mkdir -p /mnt/boot  
mount "${part}3" /mnt/boot
swapon "${part}2"

# create template for NixOS configuration
nixos-generate-config --root /mnt

# Configuration setup
tee /mnt/etc/nixos/configuration.nix > /dev/null << EOF
{ config, lib, pkgs, ... }:
let
  # Name of the configuration in the flake (nixosConfigurations.<name>), used by 'update'
  nixProfileName = "$nixProfile";
  username = "$username";
  diskName = "$diskName";
  limine = pkgs.limine.override { targets = [ "i686" "x86_64" ]; };
in
EOF

tee -a /mnt/etc/nixos/configuration.nix << 'EOF' >/dev/null
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot = {
    loader.limine = {
      enable = true;
	    biosSupport = true;
      biosDevice = "/dev/${diskName}";
      efiSupport = true;
      #
      package = limine;
      additionalFiles = {
        "EFI/BOOT/BOOTIA32.EFI" = "${limine}/share/limine/BOOTIA32.EFI";
      };
    };

    kernelPackages = pkgs.
      linuxPackages_latest
    ;

    # Clean on reboot
		tmp.cleanOnBoot = true;
  };

  # EXO Wings: firmware for the Realtek Wi-Fi (RTL8723BS/BE) and Bluetooth. Without it there may be
  # no network for 'connect-repo' (nixos-ferchu enables it too, but only after the first update).
  hardware.enableRedistributableFirmware = true;

  nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        max-jobs = 1; # EXO: 2 GB of RAM, one build at a time (the first update compiles Limine, labwc and wvkbd)
        substituters = [
            "https://cache.nixos.org"
            #"https://nix-community.cachix.org"  # si usas paquetes community
        ];
    };

  networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = true;
  time.timeZone = "America/Argentina/Buenos_Aires";

   users.users.${username} = {
     isNormalUser = true;
     extraGroups = [ "wheel" ]; # Enable "sudo" for the user.
     packages = with pkgs; [
       tree
     ];
   };

   security = {
    sudo = {
      enable = true;
      extraRules = [
        {
          users = [ username ];
          commands = [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    git
    vim

    # Custom shell script for managing GitHub deploy keys and updating from a repo.
    # You can delete this script.
    (writeShellScriptBin "createKeys" ''
        echo -e "Host github.com\n  HostName github.com\n  User git\n  IdentityFile /root/.ssh/github_deploy_key\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new" | sudo tee /root/.ssh/config > /dev/null

        sudo ssh-keygen -t ed25519 -f /root/.ssh/github_deploy_key -N "" > /dev/null

        echo "Pega esta llave que esta a continuación en tu repositorio de GitHub como deploy key:"
        echo ""
          sudo cat /root/.ssh/github_deploy_key.pub
        echo ""

        echo "Después de crear la nueva deploy key, por favor pega la URL SSH de tu repositorio aquí:"
          read repoUrl

        repoParsed=$(tr ':' '/' <<< "$repoUrl")
        echo "$repoParsed" | sudo tee /root/.github_repo_url > /dev/null

        echo ""
        echo "Repositorio se guardó correctamente: $repoParsed"
        echo ""
        echo "Ejecutando actualización..."
        echo ""

        # Reboot only if the update succeeded; otherwise keep the current system and show the error.
        if update; then
          echo "Actualización completada."
          echo "Reiniciando sistema..."

          sleep 5
          sudo reboot
          exit 0
        else
          echo "La actualización falló: no se reinicia el sistema."
          echo "Revisá el error y volvé a intentar con: update && sudo reboot"
          exit 1
        fi
    '')

    # custom shell script for updating from the GitHub repo
    # You can delete this script.
    (writeShellScriptBin "update" ''
      repo_file="/root/.github_repo_url"
      repo_url=$(sudo cat "$repo_file" | xargs) # xargs trima whitespace/newlines
      nixProfileVar="${nixProfileName}" # Nix interpolation: value comes from the 'let' at the top
      
      echo "Poner nombre de la rama del repositorio."
      echo "Si esta vacio, por defecto se usará la principal del repo."
      read -rp "Nombre de la rama: " rama < /dev/tty
      echo ""
      
      echo ""
      echo "Actualizando con repo: $repo_url"
      echo ""
      echo "Perfil de Nix: $nixProfileVar"
      echo ""

      # Pin a branch only if one was given; otherwise Nix uses the default branch of the repo.
      # In a flake URL the query (?ref=) must go before the fragment (#profile).
      if [ -n "$rama" ]; then
        repo="git+ssh://$repo_url?ref=$rama#$nixProfileVar"
      else
        repo="git+ssh://$repo_url#$nixProfileVar"
      fi

      sudo nixos-generate-config
      # DISK: install disk as a plain string (e.g. sda). The flake reads it with builtins.getEnv "DISK" (needs --impure)
      sudo DISK=${diskName} nixos-rebuild boot --flake "$repo" \
        --refresh --impure --no-write-lock-file \
        -I hardware=/etc/nixos/hardware-configuration.nix
    '')
  ];

  environment = {
    shellAliases = {
      # Alias for connecting to the GitHub repository
      connect-repo = "createKeys";
    };
  };

  services = {
    openssh = {
        enable = true;
        settings = {
            PermitRootLogin = "no";
            PasswordAuthentication = true;
            AllowGroups = [
                "wheel"
            ];   
        };
    };
  };


  networking.firewall.enable = false;
  system.stateVersion = "26.05"; # Same as nixos-ferchu: do not change
}
EOF

echo ""
echo "Now installing NixOS..."
echo ""
# Installation of NixOS and setting 'root' password
# nixos-install only asks for the root password on a terminal ([ -t 0 ]), so it is set with chpasswd
nixos-install --no-root-passwd || fail "nixos-install failed. Read the error above, fix it and run nixos-install again."
echo "root:$passwordRoot" | chpasswd -R /mnt || fail "Could not set the root password (fix it with: nixos-enter --root /mnt, then passwd)."

# Setting the new user
echo "$username:$password" | chpasswd -R /mnt || fail "Could not set the password for $username (fix it with: nixos-enter --root /mnt, then passwd $username)."
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
