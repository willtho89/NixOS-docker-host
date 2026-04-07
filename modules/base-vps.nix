{ pkgs, ... }:

let
  updateHost = pkgs.writeShellApplication {
    name = "update-host";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      repo_dir=/etc/nixos
      update_script="$repo_dir/scripts/update-host"

      if [[ ! -x "$update_script" ]]; then
        echo "Missing host checkout at $repo_dir." >&2
        echo "Initial setup on the host:" >&2
        echo "  sudo git clone https://github.com/willtho89/NixOS-docker-host.git $repo_dir" >&2
        exit 1
      fi

      exec "$update_script" "$@"
    '';
  };
in

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  services.resolved.enable = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
    ports = [ 22 ];
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.mutableUsers = false;
  security.sudo.wheelNeedsPassword = false;

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelModules = [
    "iptable_nat"
    "ip6table_nat"
    "nf_nat"
    "xt_MASQUERADE"
  ];
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    updateHost
  ];
}
