#!/usr/bin/env bash

# SUDO
sudo -i

# Ask for the disk name to use for installation
echo "Now set name of the general disk partition..."
echo "You can see it using command 'lsblk', for example you will see '/dev/vda' or '/dev/sda'"
echo "Please just add the name next to the last '/' (e.g. 'vda', 'sdb' or 'sda')"
read -rp "Disk name: " diskName < /dev/tty

# create mbr partition table
parted /dev/$diskName -- mklabel msdos

# Add the root partition. This will fill the disk except for the end part, where the swap will live.
parted /dev/$diskName -- mkpart primary 1MB -2GB

# Set the root partition’s boot flag to on. This allows the disk to be booted from.
parted /dev/$diskName -- set 1 boot on

# Finally, add a swap partition. The size required will vary according to needs, here a 8GB one is created.
parted /dev/$diskName -- mkpart primary linux-swap -2GB 100%

#Formatting
mkfs.ext4 -L nixos /dev/$diskName"1"
mkswap -L swap /dev/$diskName"2"

# mounting
mount /dev/$diskName"1" /mnt
swapon /dev/$diskName"2"

# create template for NixOS configuration
nixos-generate-config --root /mnt

# setting password for user 'root'
echo ""
echo "Now set new password for privileged user 'root'"
read -rp "Type new password: " passwordRoot < /dev/tty
echo "Password for root is saved!"

echo ""
# Setting username for new user
echo "Now set the username for the new user"
read -rp "Type username for new user: " username < /dev/tty
echo ""

# Setting password for new user
echo "Now set new password for user '$username'"
read -rp "Type new password for '$username': " password < /dev/tty

echo ""
echo "All users are set!"

# Configuration setup
tee /mnt/etc/nixos/configuration.nix > /dev/null << EOF

{ config, lib, pkgs, ... }:
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot = {
    loader.grub = {
      enable = true;
      device = "/dev/$diskName";
    };

    kernelPackages = pkgs.
      linuxPackages_latest
    ;

    # Clean on reboot
		tmp.cleanOnBoot = true;
  };

  nix.settings = {
        experimental-features = [ "nix-command" "flakes" ];
        max-jobs = "auto"; # "auto"
        substituters = [
            "https://cache.nixos.org"
            "https://nix-community.cachix.org"  # si usas paquetes community
        ];
    };

  networking.hostName = "nixos"; # Define your hostname.
  networking.networkmanager.enable = true;
  time.timeZone = "America/Argentina/Buenos_Aires";

   users.users.$username = {
     isNormalUser = true;
     extraGroups = [ "wheel" "docker" ]; # Enable "sudo" for the user.
     packages = with pkgs; [
       tree
     ];
   };

   security = {
    sudo = {
      enable = true;
      extraRules = [
        {
          users = [ "$username" ];
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
EOF

tee -a /mnt/etc/nixos/configuration.nix << 'EOF' >/dev/null

  environment.systemPackages = with pkgs; [
    git

    # Custom shell script for managing GitHub deploy keys and updating from a repo.
    # You can delete this script.
    (writeShellScriptBin "createKeys" ''
        echo -e "Host github.com\n  HostName github.com\n  User git\n  IdentityFile /root/.ssh/github_deploy_key\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new" | sudo tee /root/.ssh/config > /dev/null

        echo "Creating GitHub deploy key..."
          sudo ssh-keygen -t ed25519 -f /root/.ssh/github_deploy_key -N ""

        echo "Pega esta llave que esta a continuación en tu repositorio de GitHub como deploy key:"
        echo ""
          sudo cat /root/.ssh/github_deploy_key.pub
        echo ""

        echo "Después de crear la nueva deploy key, por favor pega la URL SSH de tu repositorio aquí:"
          read repoUrl

        repoParsed=$(tr ':' '/' <<< "$repoUrl")
        echo "$repoParsed" | sudo tee /root/.github_repo_url

        echo ""
        echo "Repositorio se guardó correctamente: $repoParsed"
        echo ""
        echo "Ejecutando actualización..."
        echo ""

        update

        echo ""
        echo "Actualización completada."
        echo "Reiniciando sistema..."

        sleep 10
        sudo reboot
        exit 0
    '')

    # custom shell script for updating from the GitHub repo
    # You can delete this script.
    (writeShellScriptBin "update" ''
      repo_file="/root/.github_repo_url"
      repo_url=$(sudo cat "$repo_file" | xargs) # xargs trima whitespace/newlines
      echo "Actualizando con repo: $repo_url"
      sudo nixos-generate-config
      sudo nixos-rebuild boot --flake "git+ssh://$repo_url#nixos" \
        --refresh --impure --no-write-lock-file \
        -I hardware=/etc/nixos/hardware-configuration.nix
    '')
  ];

  environment = {
        # Aliases de shell disponibles en todos los usuarios (interactive shells)
        shellAliases = {
            logs = "cd /var/log";
            disco = "df -h";
            connect-repo = "createKeys";
        };
  };

  services.openssh = {
        enable = true;
        settings = {
            PermitRootLogin = "yes"; # "yes" or "no"
            PasswordAuthentication = true;
            AllowGroups = [
                "wheel"
            ];   
        };
    };

  networking.firewall.enable = false;
  system.stateVersion = "26.11"; # Did you read the comment?
}
EOF

echo ""
echo "Now installing NixOS..."
echo ""
# Installation of NixOS and setting 'root' password
echo "$passwordRoot" | nixos-install

# Setting the new user
echo "$username:$password" | chpasswd -R /mnt
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