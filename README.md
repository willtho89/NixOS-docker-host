# NixOS VPS

Single-server NixOS VPS repository with a public example host config and a private local host config for real machine-specific values such as IPs, MAC addresses, and SSH access.

## Repository Layout

- `flake.nix`: root flake entrypoint
- `modules/base-vps.nix`: shared VPS defaults
- `configuration.nix`: server module
- `disko-config.nix`: disk layout for `disko`
- `host-config.example.nix`: tracked example host config
- `host-config.nix`: ignored real host config used for actual deployments

## Prerequisites

- Nix with flakes enabled on the machine you use for deployment
- SSH access to the target VPS
- A provider rescue environment or installer environment that lets you SSH in as `root` for the initial install
- A target disk device name for the VPS, for example `/dev/sda` or `/dev/vda`

## Configure A VPS

1. Copy the example config and edit the private local copy for your server:

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
- `access.adminUser`

Use `deployment.host` for the SSH endpoint you actually deploy to. That can be an IPv4 address, an IPv6 address, or a DNS name. Keep `network.ipv4Address` as the interface address in CIDR notation, for example `203.0.113.10/24`.

The flake resolves host config in this order:

- `./host-config.nix` when the repo is evaluated as a local `path:` flake
- `HOST_CONFIG_PATH=/absolute/path/to/host-config.nix` for CI or external config locations
- `./host-config.example.nix` as the safe public fallback

3. Validate the configuration locally:

```bash
nix build --no-link "path:$PWD#nixosConfigurations.server.config.system.build.toplevel"
```

## Install NixOS On A VPS Anywhere

This repo is set up for `nixos-anywhere`, which is the simplest way to install onto a remote VPS from your local machine.

1. Boot the VPS into the provider's rescue or installer environment.
2. Confirm the target disk name and network values in `host-config.nix`.
3. Install using `nixos-anywhere`:

```bash
DEPLOY_HOST=$(nix eval --raw --file ./host-config.nix deployment.host)

nix run github:nix-community/nixos-anywhere -- \
  --flake "path:$PWD#server" \
  "root@${DEPLOY_HOST}"
```

4. After the installer finishes, reboot into the new NixOS system and confirm SSH access with the admin user from `host-config.nix`.

This configuration disables direct root SSH login after installation. Use the admin user for ongoing access and elevate with `sudo` when needed.

Security defaults in the shared VPS module:

- SSH accepts logins only for `access.adminUser.name`
- SSH agent forwarding is disabled
- SSH remote port forwarding is disabled, while local port forwarding remains allowed
- `sudo` for `wheel` requires a password unless you explicitly set `access.wheelNeedsPassword = false;`
- `sshguard`, the firewall, AppArmor, and a stricter kernel/sysctl baseline are enabled
- Docker and WireGuard-style forwarding still work, but listening ports should now be declared in `network.allowedTCPPorts` and `network.allowedUDPPorts`, for example `80`, `443`, and `51820`
- Automatic upgrades are enabled by default, with a daily update at `04:30` and an allowed reboot window from `05:00` to `06:00`
- Journald is retained persistently, Docker logs go to journald, and auditd records config changes plus privilege-escalation events
- `/srv/docker/apps` and `/srv/docker/data` are owned by a dedicated service account declared under `dockerLayout.dataUser`

If your provider uses a different disk device or needs DHCP instead of static addressing, change those values in `host-config.nix` before running the install.

## Update A VPS Running NixOS

You can update from your workstation without logging into the server shell directly:

```bash
DEPLOY_HOST=$(nix eval --raw --file ./host-config.nix deployment.host)
DEPLOY_USER=$(nix eval --raw --file ./host-config.nix access.adminUser.name)

nix run nixpkgs#nixos-rebuild -- \
  --no-reexec \
  switch \
  --flake "path:$PWD#server" \
  --build-host "${DEPLOY_USER}@${DEPLOY_HOST}" \
  --target-host "${DEPLOY_USER}@${DEPLOY_HOST}" \
  --sudo
```

If you are deploying from macOS or any non-`x86_64-linux` machine, `--build-host` is required so the NixOS system is built on a Linux machine instead of locally. Using the same server for both `--build-host` and `--target-host` is the simplest option for a single VPS. `--sudo` lets `nixos-rebuild` connect as the admin user and elevate only for the privileged steps on the remote host.

You can also keep a checkout on the host itself. The recommended location for a single-server setup is `/etc/nixos`, with the repo treated as the source of truth and all changes made on your workstation first.

Initial setup on the host:

```bash
sudo git clone https://github.com/willtho89/NixOS-docker-host.git /etc/nixos
```

Host-side update workflow:

```bash
update-host
```

The installed `update-host` command forwards to `/etc/nixos/scripts/update-host`, which does three things:

- refuses to update from a dirty checkout
- runs `git pull --ff-only`
- runs `nixos-rebuild switch --flake path:/etc/nixos#server` as root, or `sudo` when needed

If you prefer to run the steps manually:

```bash
cd /etc/nixos
git pull --ff-only
sudo nixos-rebuild switch --flake path:/etc/nixos#server
```

## Automatic Updates And Auditing

The shared VPS module enables `system.autoUpgrade` by default. On the host, the generated `nixos-upgrade` job first runs `git -C /etc/nixos pull --ff-only`, then rebuilds `path:/etc/nixos#server`. If the checkout is dirty or `host-config.nix` is missing, the upgrade aborts instead of applying from an unexpected state.

Default maintenance policy:

- upgrade check at `04:30`
- automatic reboot allowed only between `05:00` and `06:00`
- settings can be overridden in `host-config.nix` under `maintenance.autoUpgrade`

Default logging and audit policy:

- persistent journald retention with overridable limits under `logging.journald`
- Docker daemon and container logs written to journald
- SSH daemon log level raised to `VERBOSE`
- audit rules for `/etc/nixos`, SSH config, sudo config, and privilege-escalation execs

Useful commands on the host:

```bash
sudo journalctl -u nixos-upgrade
sudo journalctl -u sshd
sudo journalctl CONTAINER_NAME=wg-easy
sudo journalctl CONTAINER_NAME=traefik
sudo ausearch -k priv-esc
```

## Docker Directory Ownership

The shared config gives the dedicated Docker service identity ownership of the directories containers may need to modify:

- `/srv/docker/apps` is owned by `dockerLayout.dataUser`
- `/srv/docker/data` is owned by `dockerLayout.dataUser`
- the admin user is added to that Docker data group so you keep access through group membership

Default example:

```nix
dockerLayout.dataUser = {
  name = "dockerapps";
  group = "docker-data";
  uid = 1100;
  gid = 1100;
};
```

If your compose stack currently uses `PUID` and `PGID`, update `.env` after deployment to use the dedicated Docker data user instead of your admin UID/GID. For the example above:

```dotenv
PUID=1100
PGID=1100
```

## Docker Backup To Filen

The repo can optionally back up `/srv/docker` by stopping the compose stack, creating a `.tar.zst` archive, starting the stack again, uploading the archive to `/.backups/<hostname>/` in Filen, pruning older remote backups, and removing the local archive after a successful upload.

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

Remote retention is applied after each successful upload:

- keep all backups newer than 3 days
- keep the newest backup between 3 and 14 days old
- keep the newest backup between 14 and 45 days old

Local backup history is not kept beyond the current run.

`persistent = false` means enabling or redeploying the timer does not immediately run a missed backup. Set it to `true` only if you want systemd to catch up missed runs automatically.

For restores, the module also installs `docker-filen-restore`. It downloads an archive from `/.backups/<hostname>/` and extracts it back into the parent directory of `sourceDir`. It does not stop or start containers.

Examples:

```bash
sudo docker-filen-restore latest
sudo docker-filen-restore example-vps-20260407T040000Z.tar.zst
```

## Publish This Repo

- Commit `flake.nix`, `flake.lock`, `README.md`, `modules/`, `configuration.nix`, `disko-config.nix`, and `host-config.example.nix`
- Do not commit `host-config.nix`, `secrets/`, or any other live host-specific overlays
- For another server, copy `host-config.example.nix` to `host-config.nix` and replace the values there

## CI And Automation

For a pipeline or any non-interactive deployment runner, the simplest option is to materialize `host-config.nix` inside the checkout and evaluate the repo as `path:$PWD#server`. If the host config must live outside the checkout, point `HOST_CONFIG_PATH` at that absolute path and use `--impure` on the Nix command that evaluates this flake.
