{
  system = "x86_64-linux";
  stateVersion = "25.11";
  hostName = "example-vps";
  timeZone = "Europe/Berlin";

  boot = {
    loaderDevice = "/dev/sda";
    initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "ahci"
      "sd_mod"
    ];
  };

  disk.device = "/dev/sda";

  network = {
    useDHCP = false;
    interfaceMacAddress = "00:11:22:33:44:55";
    nameservers = [
      "1.1.1.1"
      "2606:4700:4700::1111"
    ];
    allowedTCPPorts = [ 80 443 853 ];
    allowedUDPPorts = [ 80 443 51820 ];
    searchDomains = [ "example.internal" ];
    ipv4Address = "203.0.113.10/24";
    ipv4Gateway = "203.0.113.1";
    ipv6Address = "2001:db8::10/64";
    ipv6Gateway = "2001:db8::1";
    mtu = 1500;
  };

  deployment = {
    host = "203.0.113.10";
  };

  maintenance.autoUpgrade = {
    enable = true;
    repoDir = "/etc/nixos";
    dates = "04:30";
    allowReboot = true;
    rebootWindow = {
      lower = "05:00";
      upper = "06:00";
    };
  };

  logging.journald = {
    systemMaxUse = "1G";
    maxRetentionSec = "1month";
  };

  security.sshguard = {
    whitelist = [ "10.42.42.42" ];
  };

  dockerLayout.dataUser = {
    name = "dockerapps";
    group = "docker-data";
    uid = 1100;
    gid = 1100;
  };

  access = {
    wheelNeedsPassword = true;
    adminUser = {
      name = "deploy";
      group = "deploy";
      uid = 1000;
      gid = 995;
      extraGroups = [ "wheel" "docker" ];
      authorizedKeys = [
        "ssh-ed25519 AAAA... replace-me"
      ];
    };
  };

  backups.dockerToFilen = {
    enable = true;
    sourceDir = "/srv/docker/data";
    projectDir = "/srv/docker";
    composeFile = "/srv/docker/compose.yaml";
    environmentFile = "/var/lib/docker-filen-backup/backup.env";
    schedule = "*-*-* 04:00:00 UTC";
    persistent = false;
  };

  composeStack = {
    enable = false;
    serviceName = "docker-compose-apps";
    syncFiles = true;
    sourceDir = ./compose-stack;
    projectDir = "/srv/docker";
    composeFile = "/srv/docker/compose.yaml";
    useSopsSecrets = true;
    environment = {
      COMPOSE_PROFILES = "required,aiostreams,aiometadata,syncribullet,wg-easy,nzbdav,adguard,warp,librarysync,librespeed,comet,zilean,stremthru,jackettio,jackett,nzbhydra2";
    };
  };
}
