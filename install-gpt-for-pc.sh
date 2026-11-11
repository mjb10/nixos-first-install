#!/usr/bin/env bash

# Clean the terminal before proceeding with user setup
clear

# SUDO
sudo -i

# Ask for the disk name to use for installation
echo "Now set name of the general disk partition..."
echo "You can see it using command 'lsblk', for example you will see '/dev/vda' or '/dev/sda'"
echo "Please just add the name next to the last '/' (e.g. 'vda', 'sdb' or 'sda')"
read -rp "Disk name: " diskName < /dev/tty

# create gpt partition table
parted /dev/$diskName -- mklabel gpt

# Add the root partition. This will fill the disk except for the end part, where the swap will live.
parted /dev/$diskName -- mkpart root ext4 512MB -2GB

# Next, add a swap partition. The size required will vary according to needs, here a 8GB one is created.
parted /dev/$diskName -- mkpart swap linux-swap -2GB 100%

# Finally, the boot partition. NixOS by default uses the ESP (EFI system partition) as its /boot partition. It uses the initially reserved 512MiB at the start of the disk.
parted /dev/$diskName -- mkpart ESP fat32 1MB 512MB
parted /dev/$diskName -- set 3 esp on

#Formatting
mkfs.ext4 -L nixos /dev/$diskName"1"
mkswap -L swap /dev/$diskName"2"
mkfs.fat -F 32 -n boot /dev/$diskName"3"

# mounting
mount /dev/$diskName"1" /mnt
mkdir -p /mnt/boot  
mount /dev/$diskName"3" /mnt/boot
swapon /dev/$diskName"2"

# create template for NixOS configuration
nixos-generate-config --root /mnt

# Clean the terminal before proceeding with user setup
clear

# setting password for user 'root'
echo ""
echo "Now set new password for privileged user 'root'"
read -rp "Type new password: " passwordRoot < /dev/tty
echo ""
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

echo "Now set the Nix Profile name..."
echo ""
echo "ATTENTION! If you are going to connect to a repo it must match with the Nix profile name configured in your flake.nix file you intend to use."
echo "If you are not connecting to a repo, you can choose any name."
echo "The default is 'nixos'."
read -rp "Type Nix Profile name: " nixProfile < /dev/tty
nixProfile=${nixProfile:-nixos} # Use 'nixos' if left empty
echo ""

echo "Everything is set!"

# Configuration setup
tee /mnt/etc/nixos/configuration.nix > /dev/null << EOF
{ config, lib, pkgs, ... }:
let
  # Name of the configuration in the flake (nixosConfigurations.<name>), used by 'update'
  nixProfileName = "$nixProfile";
  username = "$username";
  diskName = "$diskName";
in
EOF

tee -a /mnt/etc/nixos/configuration.nix << 'EOF' >/dev/null
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot = {
    loader.grub = {
      enable = true;
      device = "/dev/${diskName}";
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

   users.users.${username} = {
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
    fail2ban
    git

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
      sudo nixos-rebuild boot --flake "$repo" \
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

  services.openssh = {
        enable = true;
        settings = {
            PermitRootLogin = "no";
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