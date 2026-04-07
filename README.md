# NixOS VPS

Single-server NixOS VPS repository with a local, git-ignored host settings file for machine-specific values such as IPs, MAC addresses, and SSH access.

Because `host-config.nix` is intentionally not tracked by git, flake-based commands in this repo must be run with impure evaluation enabled.

## Repository Layout

- `flake.nix`: root flake entrypoint
- `modules/base-vps.nix`: shared VPS defaults
- `configuration.nix`: server module
- `disko-config.nix`: disk layout for `disko`
- `host-config.example.nix`: template for machine-specific settings
- `host-config.nix`: local machine-specific settings, intentionally ignored by git

## Prerequisites

- Nix with flakes enabled on the machine you use for deployment
- SSH access to the target VPS
- A provider rescue environment or installer environment that lets you SSH in as `root`
- A target disk device name for the VPS, for example `/dev/sda` or `/dev/vda`

## Configure A VPS

1. Copy the example host settings file and edit it for your server:

```bash
cp host-config.example.nix host-config.nix
```

2. Update at least these values in `host-config.nix`:

- `hostName`
- `disk.device`
- `boot.loaderDevice`
- `network.interfaceMacAddress`
- `network.ipv4Address`
- `network.ipv4Gateway`
- `network.ipv6Address` and `network.ipv6Gateway` if your provider gives you IPv6
- `deployment.host`
- `access.rootAuthorizedKeys`
- `access.adminUser`

Use `deployment.host` for the SSH endpoint you actually deploy to. That can be an IPv4 address, an IPv6 address, or a DNS name. Keep `network.ipv4Address` as the interface address in CIDR notation, for example `203.0.113.10/24`.

3. Validate the configuration locally:

```bash
nix build --impure .#nixosConfigurations.server.config.system.build.toplevel --no-link
```

## Install NixOS On A VPS Anywhere

This repo is set up for `nixos-anywhere`, which is the simplest way to install onto a remote VPS from your local machine.

1. Boot the VPS into the provider's rescue or installer environment.
2. Confirm the target disk name and network values you will place in `host-config.nix`.
3. Install using `nixos-anywhere`:

```bash
DEPLOY_HOST=$(nix eval --impure --raw --expr '(import ./host-config.nix).deployment.host')

nix run github:nix-community/nixos-anywhere -- \
  --option pure-eval false \
  --flake .#server \
  "root@${DEPLOY_HOST}"
```

4. After the installer finishes, reboot into the new NixOS system and confirm SSH access with the admin user from `host-config.nix`.

If your provider uses a different disk device or needs DHCP instead of static addressing, change those values in `host-config.nix` before running the install.

## Update A VPS Running NixOS

You can update from your workstation without logging into the server shell directly:

```bash
DEPLOY_HOST=$(nix eval --impure --raw --expr '(import ./host-config.nix).deployment.host')

nix run nixpkgs#nixos-rebuild -- \
  --fast \
  switch \
  --flake .#server \
  --build-host "root@${DEPLOY_HOST}" \
  --target-host "root@${DEPLOY_HOST}"
```

If you are deploying from macOS or any non-`x86_64-linux` machine, `--build-host` is required so the NixOS system is built on a Linux machine instead of locally. Using the same server for both `--build-host` and `--target-host` is the simplest option for a single VPS.

Or run the switch directly on the server after pulling the repo:

```bash
sudo nixos-rebuild switch --impure --flake /path/to/repo#server
```

## Docker Backup To Filen

The repo can optionally back up `/srv/docker` by stopping the compose stack, creating a `.tar.zst` archive, starting the stack again, uploading the archive to `/.backups/<hostname>/` in Filen, and removing the local archive after a successful upload.

Enable it in `host-config.nix`:

```nix
backups.dockerToFilen = {
  enable = true;
  sourceDir = "/srv/docker";
  composeFile = "/srv/docker/compose.yaml";
  environmentFile = "/var/lib/docker-filen-backup/backup.env";
  schedule = "*-*-* 04:00:00 UTC";
  persistent = false;
};
```

Authentication is intentionally kept out of git. After deploying, use one of these approaches on the server:

- Preferred: place a Filen auth config at `/var/lib/docker-filen-backup/filen-cli/.filen-cli-auth-config`
- Simpler but less secure: create `/var/lib/docker-filen-backup/backup.env` with `FILEN_EMAIL=...` and `FILEN_PASSWORD=...`, plus `FILEN_2FA_CODE=...` if needed

If you want to generate the auth config on the server, the `filen` CLI is installed when the backup module is enabled. Point it at the backup data directory before running `filen export-auth-config`.

Remote cleanup is manual for now. The job does not keep local backup history beyond the current run.

`persistent = false` means enabling or redeploying the timer does not immediately run a missed backup. Set it to `true` only if you want systemd to catch up missed runs automatically.

For restores, the module also installs `docker-filen-restore`. It downloads an archive from `/.backups/<hostname>/` and extracts it back into the parent directory of `sourceDir`. It does not stop or start containers.

Examples:

```bash
sudo docker-filen-restore latest
sudo docker-filen-restore example-vps-20260407T040000Z.tar.zst
```

## Publish This Repo

- Commit `flake.nix`, `flake.lock`, `README.md`, `modules/`, `configuration.nix`, `disko-config.nix`, and `host-config.example.nix`
- Do not commit `host-config.nix`
- For another server, start a new repo from this one and replace the values in `host-config.nix`
