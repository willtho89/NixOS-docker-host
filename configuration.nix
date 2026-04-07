{ lib, modulesPath, hostConfig, ... }:

let
  adminUser = hostConfig.access.adminUser;
  adminGroup = adminUser.group or adminUser.name;
  adminUid = adminUser.uid or null;
  adminGid = adminUser.gid or null;
  dockerLayout = hostConfig.dockerLayout or { };
  dockerRootDir = dockerLayout.rootDir or "/srv/docker";
  dockerAppsDir = dockerLayout.appsDir or "${dockerRootDir}/apps";
  dockerDataDir = dockerLayout.dataDir or "${dockerRootDir}/data";
  dockerDataUser = dockerLayout.dataUser or { };
  dockerDataUserName = dockerDataUser.name or "dockerapps";
  dockerDataGroup = dockerDataUser.group or "docker-data";
  dockerDataUid = dockerDataUser.uid or null;
  dockerDataGid = dockerDataUser.gid or null;
  adminExtraGroups = lib.unique ([ "wheel" dockerDataGroup ] ++ (adminUser.extraGroups or [ ]));
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
    ./modules/compose-stack.nix
    ./modules/docker-compose-secrets.nix
    ./modules/docker-filen-backup.nix
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
  users.groups.${adminGroup} = lib.optionalAttrs (adminGid != null) {
    gid = adminGid;
  };
  users.groups.${dockerDataGroup} = lib.optionalAttrs (dockerDataGid != null) {
    gid = dockerDataGid;
  };
  users.users.${adminUser.name} = {
    isNormalUser = true;
    group = adminGroup;
    extraGroups = adminExtraGroups;
    openssh.authorizedKeys.keys = adminUser.authorizedKeys;
  } // lib.optionalAttrs (adminUid != null) {
    uid = adminUid;
  };
  users.users.${dockerDataUserName} = {
    isSystemUser = true;
    group = dockerDataGroup;
    description = "Docker application data owner";
    home = dockerDataDir;
    createHome = false;
  } // lib.optionalAttrs (dockerDataUid != null) {
    uid = dockerDataUid;
  };

  systemd.tmpfiles.rules = [
    "d ${dockerRootDir} 0750 ${adminUser.name} ${dockerDataGroup} -"
    "d ${dockerAppsDir} 2770 ${dockerDataUserName} ${dockerDataGroup} -"
    "d ${dockerDataDir} 2770 ${dockerDataUserName} ${dockerDataGroup} -"
    "Z ${dockerAppsDir} 2770 ${dockerDataUserName} ${dockerDataGroup} -"
    "Z ${dockerDataDir} 2770 ${dockerDataUserName} ${dockerDataGroup} -"
    "z ${dockerDataDir}/traefik/acme.json 0600 ${dockerDataUserName} ${dockerDataGroup} -"
  ];
}
