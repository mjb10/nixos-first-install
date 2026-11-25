#!/usr/bin/env bash

# Clean the terminal before proceeding with user setup
clear

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

# Setting the public address of Headscale (Tailscale coordination server that runs on this machine)
echo "Now set the domain for Headscale (the Tailscale coordination server this machine will run)..."
echo ""
echo "With a domain (recommended): it must point (DNS A/AAAA record) to the public IP of this machine, and ports 80 and 443 must be reachable: they are used to get the HTTPS certificate (Let's Encrypt)."
echo "Without a domain: leave it empty and Headscale will use plain HTTP on the IP of this machine (port 8080)."
echo "ATTENTION! Without HTTPS the devices can't verify that they are talking to your server, and some Tailscale apps may not accept it."
echo "Example: headscale.example.com"
read -rp "Type Headscale domain (empty = use the IP): " headscaleDomain < /dev/tty
# Accept it with or without 'https://' and a trailing '/'
headscaleDomain=${headscaleDomain#http://}
headscaleDomain=${headscaleDomain#https://}
headscaleDomain=${headscaleDomain%/}

if [ -n "$headscaleDomain" ]; then
  echo ""
  echo "Headscale URL: https://$headscaleDomain"
else
  # Source address of the default route: the public IP on a VPS (behind NAT it is the local IP)
  detectedIp=$(ip -4 route get 1.1.1.1 2> /dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')
  echo ""
  echo "Detected IP of this machine: ${detectedIp:-none}"
  echo "If this machine is behind NAT, type its public IP instead (and forward port 8080 to it)."
  while [ -z "$headscaleIp" ]; do
    read -rp "Type the IP for Headscale (empty = detected IP): " headscaleIp < /dev/tty
    headscaleIp=${headscaleIp:-$detectedIp}
  done
  echo ""
  echo "Headscale URL: http://$headscaleIp:8080"
fi
echo ""

echo "Everything is set!"

# Configuration setup
tee /mnt/etc/nixos/configuration.nix > /dev/null << EOF
{ config, lib, pkgs, ... }:
let
  # Name of the configuration in the flake (nixosConfigurations.<name>), used by 'update'
  nixProfileName = "$nixProfile";
  username = "$username";
  # Headscale public address: with a domain, server_url = https://<domain> (through Caddy);
  # with an empty domain, server_url = http://<headscaleIp>:8080 (plain HTTP, no Caddy)
  headscaleDomain = "$headscaleDomain";
  headscaleIp = "$headscaleIp";
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
      biosDevice = "/dev/vda";
      efiSupport = true;
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
    git
    vim
    tailscale

    # Custom shell script for managing GitHub deploy keys and updating from a repo.
    # You can delete this script.
    (writeShellScriptBin "createKeys" ''
        echo -e "Host github.com\n  HostName github.com\n  User git\n  IdentityFile /root/.ssh/github_deploy_key\n  IdentitiesOnly yes\n  StrictHostKeyChecking accept-new" | sudo tee /root/.ssh/config > /dev/null

        sudo ssh-keygen -t ed25519 -f /root/.ssh/github_deploy_key -N ""  > /dev/null

        echo "Pega esta llave que esta a continuación en tu repositorio de GitHub como deploy key:"
        echo ""
          sudo cat /root/.ssh/github_deploy_key.pub
        echo ""

        echo "Después de crear la nueva deploy key, por favor pega la URL SSH de tu repositorio aquí:"
          read repoUrl

        repoParsed=$(tr ':' '/' <<< "$repoUrl")
        echo "$repoParsed" | sudo tee /root/.github_repo_url  > /dev/null

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
      # DISK: install disk as a plain string (e.g. /dev/sda). The flake reads it with builtins.getEnv "DISK" (needs --impure)
      sudo DISK=/dev/vda nixos-rebuild boot --flake "$repo" \
        --refresh --impure --no-write-lock-file \
        -I hardware=/etc/nixos/hardware-configuration.nix
    '')

    # Custom shell script that creates a one-time pre-auth key to join another device to the tailnet.
    # You can delete this script.
    (writeShellScriptBin "tailnet-key" ''
      user="${username}" # Nix interpolation: headscale user (same name as the Linux user)
      loginServer="${config.services.headscale.settings.server_url}" # Nix interpolation: https://<domain> or http://<ip>:8080
      jq="${lib.getExe pkgs.jq}"

      userId=$(sudo headscale users list --name "$user" --output json | "$jq" -r '.[0].id // empty')
      if [ -z "$userId" ]; then
        sudo headscale users create "$user" > /dev/null || exit 1
        userId=$(sudo headscale users list --name "$user" --output json | "$jq" -r '.[0].id // empty')
      fi

      key=$(sudo headscale preauthkeys create --user "$userId" --expiration 1h) || exit 1

      echo "Clave de un solo uso para sumar un dispositivo a la tailnet (vence en 1 hora)."
      echo ""
      echo "En el dispositivo nuevo (Linux, con Tailscale instalado), ejecutá:"
      echo ""
      echo "  sudo tailscale up --login-server $loginServer --auth-key $key"
      echo ""
      echo "En las apps de Tailscale (Android, iOS, macOS, Windows): configurá $loginServer como"
      echo "servidor de coordinación personalizado e iniciá sesión. La página que se abre muestra el comando"
      echo "'headscale auth register --auth-id ... --user USERNAME': ejecutalo acá con sudo y --user $user."
    '')
  ];

  environment = {
    shellAliases = {
      # Alias for connecting to the GitHub repository
      connect-repo = "createKeys";
    };
  };

  services = {
    # Headscale: coordination server (control plane) of the tailnet.
    # With a domain it is published by Caddy on https://<headscaleDomain>; without one, on http://<headscaleIp>:8080.
    # Other devices join with 'tailscale up --login-server <server_url>' (see 'tailnet-key').
    headscale = {
      enable = true;
      # With a domain, only reachable through Caddy; without one, on every interface (plain HTTP)
      address = if headscaleDomain != "" then "127.0.0.1" else "0.0.0.0";
      port = 8080;
      settings = {
        server_url =
          if headscaleDomain != ""
          then "https://${headscaleDomain}"
          else "http://${headscaleIp}:${toString config.services.headscale.port}";
        dns = {
          magic_dns = true;
          # Devices are reachable as <hostname>.tailnet.internal (it must differ from the server_url domain)
          base_domain = "tailnet.internal";
          # Keep the DNS servers of each device; MagicDNS still resolves the tailnet names
          override_local_dns = false;
        };
      };
    };

    # Only with a domain: reverse proxy with automatic HTTPS (Let's Encrypt) for headscale.
    # The domain must point to this machine, with ports 80 and 443 reachable (the firewall is disabled).
    caddy = lib.mkIf (headscaleDomain != "") {
      enable = true;
      virtualHosts.${headscaleDomain}.extraConfig = ''
        reverse_proxy 127.0.0.1:${toString config.services.headscale.port}
      '';
    };

    # Tailscale client: this machine is also a node of its own tailnet (see systemd.services.tailnet-join).
    tailscale.enable = true;
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

  # Joins this machine to its own tailnet at boot while Tailscale is not logged in (normally only the first boot),
  # so it is reachable from the other devices. The pre-auth key is created locally and is never shown nor saved.
  systemd.services.tailnet-join = {
    description = "Join this machine to its own headscale tailnet";
    after = [ "headscale.service" "tailscaled.service" ];
    requires = [ "headscale.service" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.headscale.package config.services.tailscale.package pkgs.jq ];
    serviceConfig.Type = "oneshot";
    script = ''
      user="${username}" # Nix interpolation: headscale user (same name as the Linux user)

      # Wait until headscale answers and tailscaled reports a stable state
      state=""
      for _ in $(seq 1 30); do
        state=$(tailscale status --json --peers=false 2> /dev/null | jq -r '.BackendState' || true)
        if headscale users list > /dev/null 2>&1; then
          case "$state" in
            NeedsLogin|NeedsMachineAuth|Running|Stopped) break ;;
          esac
        fi
        sleep 2
      done

      # Already in the tailnet (or stopped on purpose with 'tailscale down'): nothing to do
      if [ "$state" != "NeedsLogin" ]; then
        echo "Tailscale state: $state. Nothing to do."
        exit 0
      fi

      userId=$(headscale users list --name "$user" --output json | jq -r '.[0].id // empty')
      if [ -z "$userId" ]; then
        headscale users create "$user" > /dev/null
        userId=$(headscale users list --name "$user" --output json | jq -r '.[0].id // empty')
      fi
      key=$(headscale preauthkeys create --user "$userId" --expiration 10m)

      # Local login server: works with or without a domain, even before the HTTPS certificate is ready.
      # --accept-dns=false: this machine keeps its own DNS servers.
      tailscale up \
        --login-server "http://127.0.0.1:${toString config.services.headscale.port}" \
        --auth-key "$key" \
        --accept-dns=false \
        --timeout 2m
    '';
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