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
- `access.rootAuthorizedKeys`
- `access.adminUser`

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
nix run github:nix-community/nixos-anywhere -- \
  --option pure-eval false \
  --flake .#server \
  root@<server-ip-or-dns>
```

4. After the installer finishes, reboot into the new NixOS system and confirm SSH access with the admin user from `host-config.nix`.

If your provider uses a different disk device or needs DHCP instead of static addressing, change those values in `host-config.nix` before running the install.

## Update A VPS Running NixOS

You can update from your workstation without logging into the server shell directly:

```bash
nix run nixpkgs#nixos-rebuild -- \
  --impure \
  --fast \
  switch \
  --flake .#server \
  --build-host root@<server-ip-or-dns> \
  --target-host root@<server-ip-or-dns>
```

If you are deploying from macOS or any non-`x86_64-linux` machine, `--build-host` is required so the NixOS system is built on a Linux machine instead of locally. Using the same server for both `--build-host` and `--target-host` is the simplest option for a single VPS.

Or run the switch directly on the server after pulling the repo:

```bash
sudo nixos-rebuild switch --impure --flake /path/to/repo#server
```

## Publish This Repo

- Commit `flake.nix`, `flake.lock`, `README.md`, `modules/`, `configuration.nix`, `disko-config.nix`, and `host-config.example.nix`
- Do not commit `host-config.nix`
- For another server, start a new repo from this one and replace the values in `host-config.nix`
