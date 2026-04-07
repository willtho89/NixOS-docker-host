{ lib, modulesPath, hostConfig, ... }:

let
  adminUser = hostConfig.access.adminUser;
  adminGroup = adminUser.group or adminUser.name;
  network = hostConfig.network;
  ipv4Address = network.ipv4Address or null;
  ipv6Address = network.ipv6Address or null;
  ipv4Gateway = network.ipv4Gateway or null;
  ipv6Gateway = network.ipv6Gateway or null;
in

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./modules/base-vps.nix
  ];

  system.stateVersion = hostConfig.stateVersion;

  networking.hostName = hostConfig.hostName;
  time.timeZone = hostConfig.timeZone;

  boot.loader.grub = {
    enable = true;
    device = hostConfig.boot.loaderDevice;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.initrd.availableKernelModules = hostConfig.boot.initrd.availableKernelModules;

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = network.useDHCP or false;
  networking.nameservers = network.nameservers;

  systemd.network.networks."10-wan" = {
    matchConfig = {
      MACAddress = network.interfaceMacAddress;
    };

    networkConfig = {
      DHCP = if network.useDHCP or false then "yes" else "no";
      IPv6AcceptRA = network.ipv6AcceptRA or false;
      DNS = network.nameservers;
      Domains = network.searchDomains or [ ];
    } // lib.optionalAttrs (ipv4Gateway != null) {
      Gateway = ipv4Gateway;
    };

    address =
      lib.optional (ipv4Address != null) ipv4Address
      ++ lib.optional (ipv6Address != null) ipv6Address;

    routes = lib.optional (ipv6Gateway != null) {
      Destination = "::/0";
      Gateway = ipv6Gateway;
      GatewayOnLink = network.ipv6GatewayOnLink or true;
    };

    linkConfig = {
      RequiredForOnline = "routable";
      MTUBytes = toString (network.mtu or 1500);
    };
  };

  users.users.root.openssh.authorizedKeys.keys = hostConfig.access.rootAuthorizedKeys;

  users.groups.${adminGroup} = { };
  users.users.${adminUser.name} = {
    isNormalUser = true;
    group = adminGroup;
    extraGroups = adminUser.extraGroups;
    openssh.authorizedKeys.keys = adminUser.authorizedKeys;
  };

  systemd.tmpfiles.rules = [
    "d /srv/docker 0755 ${adminUser.name} ${adminGroup} -"
  ];
}
