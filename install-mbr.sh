#!/usr/bin/env bash

# SUDO
sudo -i

# create mbr partition table
parted /dev/vda -- mklabel msdos

# Add the root partition. This will fill the disk except for the end part, where the swap will live.
parted /dev/vda -- mkpart primary 1MB -1GB

# Set the root partition’s boot flag to on. This allows the disk to be booted from.
parted /dev/vda -- set 1 boot on

# Finally, add a swap partition. The size required will vary according to needs, here a 8GB one is created.
parted /dev/vda -- mkpart primary linux-swap -1GB 100%

#Formatting
mkfs.ext4 -L nixos /dev/vda1
mkswap -L swap /dev/vda2

# mounting
mount /dev/vda1 /mnt
swapon /dev/vda2

# create template for NixOS configuration
nixos-generate-config --root /mnt

# Configuration startup
tee /mnt/etc/nixos/configuration.nix > /dev/null << 'EOF'

# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  # Use the GRUB 2 boot loader.
  boot = {
    loader.grub = {
      enable = true;
      device = "/dev/vda";
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

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Argentina/Buenos_Aires";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  # Configure keymap in X11
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # services.pulseaudio.enable = true;
  # OR
  # services.pipewire = {
  #   enable = true;
  #   pulse.enable = true;
  # };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.libinput.enable = true;

  # Define a user account. Don't forget to set a password with "passwd".
   users.users.nixi = {
     isNormalUser = true;
     extraGroups = [ "wheel" "docker" ]; # Enable "sudo" for the user.
     packages = with pkgs; [
       tree
     ];
   };

  # programs.firefox.enable = true;

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    # - Security tools
    fail2ban

    # - System utilities
    git
    btop

    (writeShellScriptBin "createKeys" ''
        sudo -i
        
        tee /root/.ssh/config <<EOF
          Host github.com
          HostName github.com
          User git
          IdentityFile /root/.ssh/github_deploy_key
          IdentitiesOnly yes
          StrictHostKeyChecking accept-new
        EOF

        echo "Creating GitHub deploy key..." &&
          ssh-keygen -t ed25519 -f /root/.ssh/github_deploy_key -N ""
              
        echo "Pega esta llave que esta a continuación en tu repositorio de GitHub como deploy key."
        echo ""
          cat /root/.ssh/github_deploy_key.pub
        echo ""

        echo "Después de crear la nueva deploy key, por favor pega la URL SSH de tu repositorio aquí:"
          read repoUrl

        echo "$repoUrl" > /root/.github_repo_url

        echo "Repositorio se guardó correctamente."
        echo "Ejecutando actualización..."
        update
              
        echo ""
        echo "Actualización completada."
        echo "Reiniciando sistema..."
              
          sleep 5
        sudo reboot
        exit 0
    '')
  ];

  environment = {
        # Aliases de shell disponibles en todos los usuarios (interactive shells)
        shellAliases = {
            #update = "sudo nixos-generate-config && sudo nixos-rebuild switch --flake git+ssh://git@github.com/mjb10/nixos-server#nixos --refresh --impure --no-write-lock-file -I hardware=/etc/nixos/hardware-configuration.nix";
             update = ''
                bash -c '
                  repo_file="/root/.github_repo_url"
                  if [ -f "$repo_file" ]; then
                    repo_url=$(cat "$repo_file" | xargs) # xargs trima whitespace/newlines
                    if [ -n "$repo_url" ]; then
                      echo "Actualizando con repo: $repo_url"
                      sudo nixos-generate-config && \
                      sudo nixos-rebuild switch --flake "git+ssh://$repo_url#nixos" \
                        --refresh --impure --no-write-lock-file \
                        -I hardware=/etc/nixos/hardware-configuration.nix
                    else
                      echo "Error: $repo_file está vacío" >&2
                      exit 1
                    fi
                  else
                    echo "Error: No existe $repo_file" >&2
                    exit 1
                  fi
                '
              '';
            logs = "cd /var/log";
            disco = "df -h";
            createDeployKeys = "createKeys";
            connectRepo = "createKeys";
            connect-repo = "createKeys";
        };
  };

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
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

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you

  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
  # to actually do that.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "26.11"; # Did you read the comment?
}
EOF

# setting password for user 'root'
echo "Now set new password for user 'root'"
echo "Type new password: "
read -s passwordRoot

# Installation of NixOS
echo "$passwordRoot" | nixos-install

# Setting password for Nixi
echo "Now set new password for user 'nixi'"
echo "Type new password: "
read -s password
echo "$password" | nixos-enter --root /mnt -c 'passwd nixi'

echo "Everything's done!"
echo "Now shutting down the system..."
echo "Don't forget to remove the installation media and then boot the system!"
sleep 5

# shutdown the system after installationr
poweroff