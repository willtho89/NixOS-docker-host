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

  access = {
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
    sourceDir = "/srv/docker";
    composeFile = "/srv/docker/compose.yaml";
    environmentFile = "/var/lib/docker-filen-backup/backup.env";
    schedule = "*-*-* 04:00:00 UTC";
    persistent = false;
  };
}
