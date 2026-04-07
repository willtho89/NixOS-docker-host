{ pkgs, ... }:

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
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = 1;
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
  ];
}
