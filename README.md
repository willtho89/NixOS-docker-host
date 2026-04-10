# NixOS VPS

This repository manages a single NixOS server with:

- a reusable host config pattern
- remote install and update workflows
- optional managed Docker Compose services under `/srv/docker`
- `sops-nix` for encrypted secrets
- an optional Filen backup job for Docker data

## Repository Layout

- `flake.nix`: flake entrypoint
- `configuration.nix`: main system configuration
- `disko-config.nix`: disk layout for `disko`
- `host-config.example.nix`: public example host settings
- `host-config.nix`: ignored private host settings used for real deployments
- `modules/base-vps.nix`: shared VPS defaults
- `modules/compose-stack.nix`: managed Docker Compose service
- `modules/docker-compose-secrets.nix`: `sops` integration for the compose stack
- `modules/docker-filen-backup.nix`: Filen backup and restore tooling
- `compose-stack/`: tracked compose project files
- `secrets/`: encrypted host secrets
- `scripts/update-host`: host-side pull and rebuild helper

## Prerequisites

- Nix with flakes enabled on the machine used for deployment
- SSH access to the target VPS
- A rescue or installer environment that allows root SSH for the first install
- The target disk device name, such as `/dev/sda` or `/dev/vda`

## Configure A Host

Copy the example config:

```bash
cp host-config.example.nix host-config.nix
```

Update at least these values in `host-config.nix`:

- `hostName`
- `disk.device`
- `boot.loaderDevice`
- `network.interfaceName`
- `network.ipv4Address`
- `network.ipv4Gateway`
- `network.ipv6Address` and `network.ipv6Gateway` if used
- `deployment.host`
- `access.adminUser`

The flake resolves host config in this order:

1. `./host-config.nix`
2. `HOST_CONFIG_PATH=/absolute/path/to/host-config.nix`
3. `./host-config.example.nix`

Validate locally:

```bash
nix build --no-link "path:$PWD#nixosConfigurations.server.config.system.build.toplevel"
```

From macOS or any other non-Linux workstation, use a structural check locally:

```bash
nix flake check --no-build --all-systems
```

Build the full NixOS system closure on a Linux builder or on the target host.

If you use `HOST_CONFIG_PATH`, evaluate with `--impure`.

## Install A New VPS

This repository is designed to work with `nixos-anywhere`.

1. Boot the server into the provider rescue or installer environment.
2. Verify the disk and network values in `host-config.nix`.
3. Run the install:

```bash
DEPLOY_HOST=$(nix eval --raw --file ./host-config.nix deployment.host)

nix run github:nix-community/nixos-anywhere -- \
  --flake "path:$PWD#server" \
  "root@${DEPLOY_HOST}"
```

After installation, log in as the configured admin user. Direct root SSH login is disabled by the system configuration after deploy.

## Update The Server

Remote rebuild from your workstation:

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

Using `--build-host` is the simplest way to deploy from macOS or any non-Linux workstation.

If you also keep a checkout on the host, the expected location is `/etc/nixos`. Host-side updates then look like this:

```bash
sudo git clone <repo-url> /etc/nixos
```

Then:

```bash
update-host
```

That helper refuses to run from a dirty checkout, pulls with `git pull --ff-only`, and runs `nixos-rebuild switch`.

## Operational Defaults

The shared VPS module enables a sensible baseline by default:

- firewall enabled
- OpenSSH restricted to the configured admin user
- persistent journald storage
- `sshguard`, AppArmor, and auditd enabled
- Docker enabled with journald logging
- automatic upgrades enabled by default

The default upgrade schedule is `04:30`, with automatic reboot allowed from `05:00` to `06:00`.

Adjust host-specific values in `host-config.nix`.

## Managed Compose Stack

The compose stack is optional and can be managed by systemd.

Example:

```nix
composeStack = {
  enable = true;
  syncFiles = true;
  sourceDir = ./compose-stack;
  projectDir = "/srv/docker";
  composeFile = "/srv/docker/compose.yaml";
  useSopsSecrets = true;
  environment = {
    COMPOSE_PROFILES = "required,aiostreams,aiometadata,syncribullet,wg-easy,nzbdav,adguard,warp,librarysync,librespeed,comet,zilean,stremthru,jackettio,jackett,nzbhydra2";
  };
};
```

When enabled, the module:

- syncs tracked files from `compose-stack/` into `/srv/docker`
- keeps mutable app data in `/srv/docker/data`
- can render secret-backed environment files and config via `sops`
- starts the stack with `docker compose up -d --remove-orphans`

Important: do not keep runtime-generated state under `/srv/docker/apps`. The sync step manages that tree and may delete unmanaged files there. Persistent data should live under `/srv/docker/data`.

## Docker Directory Ownership

The configuration creates a dedicated service user for Docker-managed data. By default:

```nix
dockerLayout.dataUser = {
  name = "dockerapps";
  group = "docker-data";
  uid = 1100;
  gid = 1100;
};
```

The managed directories are:

- `/srv/docker/apps`
- `/srv/docker/data`

If your compose services use `PUID` and `PGID`, point them at this Docker data user rather than the admin account.

## Encrypted Secrets

Secrets are handled with `sops-nix`.

- `.sops.yaml` defines the repository policy
- `secrets/<hostname>.yaml` holds the encrypted values for a host
- the host decrypts using `/etc/ssh/ssh_host_ed25519_key`

Edit a secret file with:

```bash
XDG_CACHE_HOME=/tmp/nix-cache nix shell nixpkgs#sops -c sops secrets/<hostname>.yaml
```

If `composeStack.useSopsSecrets = true;`, the compose module renders secret-backed files from the encrypted host secret file instead of relying on plaintext values in the tracked compose tree.

### After First Install Or Reinstall

This repository uses the host's `/etc/ssh/ssh_host_ed25519_key` as the machine-side `sops` identity. A fresh install or reinstall generates a new host key, so the tracked secret file must be rekeyed for that new machine before `sops-nix` can decrypt on the host.

1. Fetch the current host SSH public key:

```bash
ssh <admin-user>@<host> 'sudo cat /etc/ssh/ssh_host_ed25519_key.pub'
```

2. Convert it to an age recipient:

```bash
printf '%s\n' 'ssh-ed25519 AAAA... root@host' > /tmp/host_ed25519.pub
XDG_CACHE_HOME=/tmp/nix-cache nix shell nixpkgs#ssh-to-age -c ssh-to-age -i /tmp/host_ed25519.pub
```

3. Replace the host recipient in `.sops.yaml` with the new `age...` value.

4. Rekey the host secret file:

```bash
XDG_CACHE_HOME=/tmp/nix-cache nix shell nixpkgs#sops -c sops updatekeys -y secrets/<hostname>.yaml
```

If your admin SSH private key is stored under a non-default filename, point `sops` at it explicitly:

```bash
SOPS_AGE_SSH_PRIVATE_KEY_FILE=~/.ssh/<your-private-key> \
XDG_CACHE_HOME=/tmp/nix-cache nix shell nixpkgs#sops -c sops updatekeys -y secrets/<hostname>.yaml
```

5. Apply the updated configuration again so the host can decrypt and render the secret-backed files:

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

## Docker Backup To Filen

The Filen backup module is optional and archives `/srv/docker/data` by stopping the compose stack, creating a compressed archive, uploading it, pruning old remote backups, and removing the local archive after success.

By default, the backup module assumes the managed compose stack from this repository is enabled. If you intentionally point it at an external compose project, set `backups.dockerToFilen.allowUnmanagedCompose = true;`.

Example:

```nix
backups.dockerToFilen = {
  enable = true;
  sourceDir = "/srv/docker/data";
  projectDir = "/srv/docker";
  composeFile = "/srv/docker/compose.yaml";
  environmentFile = "/var/lib/docker-filen-backup/backup.env";
  schedule = "*-*-* 04:00:00 UTC";
  persistent = false;
};
```

Authentication can come from either:

- `/var/lib/docker-filen-backup/filen-cli/.filen-cli-auth-config`
- `/var/lib/docker-filen-backup/backup.env`

Restore commands:

```bash
sudo docker-filen-restore latest
sudo docker-filen-restore example-vps-20260407T040000Z.tar.zst
```

This restores Docker data only. Managed compose files should be restored by redeploying the NixOS config.

## What To Commit

Commit:

- `flake.nix`
- `flake.lock`
- `.sops.yaml`
- `README.md`
- `configuration.nix`
- `disko-config.nix`
- `modules/`
- `host-config.example.nix`
- `compose-stack/`
- encrypted files under `secrets/`

Do not commit:

- `host-config.nix`
- unencrypted secrets
- ad hoc host-specific files that are not meant to be shared
