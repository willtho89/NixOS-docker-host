{ hostConfig, pkgs, ... }:

let
  adminUser = hostConfig.access.adminUser.name;
  wheelNeedsPassword = hostConfig.access.wheelNeedsPassword or true;
  allowedTCPPorts = hostConfig.network.allowedTCPPorts or [ ];
  allowedUDPPorts = hostConfig.network.allowedUDPPorts or [ ];
  sshguard = hostConfig.security.sshguard or { };
  sshguardWhitelist = sshguard.whitelist or [ ];
  autoUpgrade = hostConfig.maintenance.autoUpgrade or { };
  autoUpgradeRepoDir = autoUpgrade.repoDir or "/etc/nixos";
  autoUpgradeDates = autoUpgrade.dates or "04:30";
  autoUpgradeRebootWindow = autoUpgrade.rebootWindow or {
    lower = "05:00";
    upper = "06:00";
  };
  journald = hostConfig.logging.journald or { };
  journaldSystemMaxUse = journald.systemMaxUse or "1G";
  journaldMaxRetentionSec = journald.maxRetentionSec or "1month";
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

  networking.firewall = {
    enable = true;
    allowedTCPPorts = allowedTCPPorts;
    allowedUDPPorts = allowedUDPPorts;
    logRefusedConnections = true;
  };

  services.resolved.enable = true;
  services.sshguard = {
    enable = true;
    whitelist = sshguardWhitelist;
  };
  services.journald = {
    storage = "persistent";
    extraConfig = ''
      Compress=yes
      Seal=yes
      SystemMaxUse=${journaldSystemMaxUse}
      MaxRetentionSec=${journaldMaxRetentionSec}
    '';
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    ports = [ 22 ];
    settings = {
      AllowAgentForwarding = false;
      AllowUsers = [ adminUser ];
      AllowTcpForwarding = "local";
      Compression = false;
      LoginGraceTime = 30;
      MaxAuthTries = 3;
      MaxSessions = 4;
      MaxStartups = "10:30:60";
      PermitUserEnvironment = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      LogLevel = "VERBOSE";
      X11Forwarding = false;
    };
  };

  security.audit.enable = true;
  security.auditd.enable = true;
  security.audit.rules = [
    "-w /etc/nixos/ -p wa -k nixos-config"
    "-w /etc/ssh/sshd_config -p wa -k ssh-config"
    "-w /etc/sudoers -p wa -k sudo-config"
    "-a always,exit -F arch=b64 -S execve -C uid!=euid -F euid=0 -k priv-esc"
    "-a always,exit -F arch=b32 -S execve -C uid!=euid -F euid=0 -k priv-esc"
  ];
  security.apparmor.enable = true;
  users.mutableUsers = false;
  security.sudo.wheelNeedsPassword = wheelNeedsPassword;
  systemd.coredump.enable = false;
  system.autoUpgrade = {
    enable = autoUpgrade.enable or true;
    flake = "path:${autoUpgradeRepoDir}#server";
    flags = autoUpgrade.flags or [ ];
    dates = autoUpgradeDates;
    allowReboot = autoUpgrade.allowReboot or true;
    rebootWindow = autoUpgradeRebootWindow;
    operation = autoUpgrade.operation or "switch";
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    logDriver = "journald";
  };

  systemd.services.nixos-upgrade.preStart = ''
    repo_dir=${autoUpgradeRepoDir}

    if [[ ! -d "$repo_dir/.git" ]]; then
      echo "Missing git checkout for automatic updates at $repo_dir" >&2
      exit 1
    fi

    if [[ ! -f "$repo_dir/host-config.nix" ]]; then
      echo "Missing host config for automatic updates at $repo_dir/host-config.nix" >&2
      exit 1
    fi

    if [[ -n "$(git -C "$repo_dir" status --porcelain)" ]]; then
      echo "Refusing automatic update from dirty checkout: $repo_dir" >&2
      exit 1
    fi

    git -C "$repo_dir" pull --ff-only
  '';
  systemd.services.nixos-upgrade.path = [ pkgs.git ];

  boot.loader.efi.canTouchEfiVariables = false;
  boot.kernelModules = [
    "iptable_nat"
    "ip6table_nat"
    "nf_nat"
    "xt_MASQUERADE"
  ];
  boot.kernel.sysctl = {
    "net.core.rmem_default" = 8388608;
    "net.core.rmem_max" = 8388608;
    "net.core.wmem_default" = 8388608;
    "net.core.wmem_max" = 8388608;
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
    "vm.overcommit_memory" = 1;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.unprivileged_bpf_disabled" = 1;
    "kernel.yama.ptrace_scope" = 2;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
    updateHost
  ];
}
