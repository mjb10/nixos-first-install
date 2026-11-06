#!/usr/bin/env bash

# SUDO
sudo -i

# create gpt partition table
parted /dev/vda -- mklabel gpt

# Add the root partition. This will fill the disk except for the end part, where the swap will live.
parted /dev/vda -- mkpart root ext4 512MB -1GB

# Next, add a swap partition. The size required will vary according to needs, here a 8GB one is created.
parted /dev/vda -- mkpart swap linux-swap -1GB 100%

# Finally, the boot partition. NixOS by default uses the ESP (EFI system partition) as its /boot partition. It uses the initially reserved 512MiB at the start of the disk.
parted /dev/vda -- mkpart ESP fat32 1MB 512MB
parted /dev/vda -- set 3 esp on

#Formatting
mkfs.ext4 -L nixos /dev/vda1
mkswap -L swap /dev/vda2
mkfs.fat -F 32 -n boot /dev/vda3

# mounting
mount /dev/vda1 /mnt
mkdir -p /mnt/boot  
mount /dev/vda3 /mnt/boot
swapon /dev/vda2

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
read -rp "Type new password: " password < /dev/tty

echo ""
echo "All users are set!"

# Configuration startup
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
      device = "/dev/vda";
    };

    kernelPackages = pkgs.
      linuxPackages_latest
    ;

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

  environment.systemPackages = with pkgs; [
    fail2ban

    git
    btop

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
            #update = "sudo nixos-generate-config && sudo nixos-rebuild switch --flake git+ssh://git@github.com/mjb10/nixos-server#nixos --refresh --impure --no-write-lock-file -I hardware=/etc/nixos/hardware-configuration.nix";
             update = ''
                bash -c '
                  repo_file="/root/.github_repo_url"
                  repo_url=$(cat "$repo_file" | xargs) # xargs trima whitespace/newlines
                  echo "Actualizando con repo: $repo_url"
                  sudo nixos-generate-config && \
                  sudo nixos-rebuild switch --flake "git+ssh://$repo_url#nixos" \
                    --refresh --impure --no-write-lock-file \
                    -I hardware=/etc/nixos/hardware-configuration.nix
                '
              '';
            logs = "cd /var/log";
            disco = "df -h";
            createDeployKeys = "createKeys";
            connectRepo = "createKeys";
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
# Installation of NixOS
echo "$passwordRoot" | nixos-install

echo "$username:$password" | chpasswd -R /mnt
echo ""

echo "Everything's done!"
echo "Now shutting down the system..."
echo "Don't forget to remove the installation media and then boot the system!"
sleep 5

# shutdown the system after installationr
poweroff