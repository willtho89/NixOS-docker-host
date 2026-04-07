{ lib, pkgs, hostConfig, ... }:

let
  cfg = hostConfig.backups.dockerToFilen or { };
  enabled = cfg.enable or false;
  serviceName = "docker-filen-backup";
  sourceDir = cfg.sourceDir or "/srv/docker";
  composeFile = cfg.composeFile or "${sourceDir}/compose.yaml";
  stateDir = cfg.stateDir or "/var/lib/${serviceName}";
  archiveDir = cfg.archiveDir or "${stateDir}/archives";
  filenDataDir = cfg.filenDataDir or "${stateDir}/filen-cli";
  environmentFile = cfg.environmentFile or "${stateDir}/backup.env";
  remoteBaseDir = cfg.remoteBaseDir or "/.backups";
  remoteHostDir = cfg.remoteHostDir or "${remoteBaseDir}/${hostConfig.hostName}";
  schedule = cfg.schedule or "*-*-* 04:00:00 UTC";
  persistent = cfg.persistent or false;

  backupScript = pkgs.writeShellApplication {
    name = serviceName;
    runtimeInputs = with pkgs; [
      coreutils
      docker
      filen-cli
      findutils
      gnutar
      zstd
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      source_dir=${lib.escapeShellArg sourceDir}
      compose_file=${lib.escapeShellArg composeFile}
      archive_dir=${lib.escapeShellArg archiveDir}
      filen_data_dir=${lib.escapeShellArg filenDataDir}
      environment_file=${lib.escapeShellArg environmentFile}
      remote_base_dir=${lib.escapeShellArg remoteBaseDir}
      remote_host_dir=${lib.escapeShellArg remoteHostDir}
      archive_prefix=${lib.escapeShellArg hostConfig.hostName}

      containers_down=0
      tmp_archive=""

      log() {
        printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
      }

      cleanup() {
        local status=$?

        if [[ -n "$tmp_archive" && -f "$tmp_archive" ]]; then
          rm -f "$tmp_archive"
        fi

        if (( containers_down == 1 )); then
          log "Backup exited early, bringing containers back up"
          if ! docker compose --project-directory "$source_dir" -f "$compose_file" up -d; then
            log "Failed to restart containers automatically"
          fi
        fi

        exit "$status"
      }
      trap cleanup EXIT

      require_filen_auth() {
        if [[ -n "''${FILEN_EMAIL:-}" && -z "''${FILEN_PASSWORD:-}" ]]; then
          log "FILEN_EMAIL is set but FILEN_PASSWORD is missing in $environment_file"
          exit 1
        fi

        if [[ -z "''${FILEN_EMAIL:-}" && ! -f "$filen_data_dir/.filen-cli-auth-config" ]]; then
          log "Missing Filen credentials. Put .filen-cli-auth-config in $filen_data_dir or set FILEN_EMAIL/FILEN_PASSWORD in $environment_file"
          exit 1
        fi
      }

      filen_cmd() {
        filen --skip-update "$@"
      }

      ensure_remote_dir() {
        local path="$1"

        if ! filen_cmd ls "$path" >/dev/null 2>&1; then
          log "Creating remote directory $path"
          filen_cmd mkdir "$path"
        fi
      }

      if [[ ! -d "$source_dir" ]]; then
        log "Source directory $source_dir does not exist"
        exit 1
      fi

      if [[ ! -f "$compose_file" ]]; then
        log "Compose file $compose_file does not exist"
        exit 1
      fi

      mkdir -p "$archive_dir" "$filen_data_dir"
      export FILEN_CLI_DATA_DIR="$filen_data_dir"
      require_filen_auth

      timestamp=$(date -u +%Y%m%dT%H%M%SZ)
      archive_name="$archive_prefix-$timestamp.tar.zst"
      archive_path="$archive_dir/$archive_name"
      tmp_archive="$archive_path.tmp"

      log "Stopping containers from $compose_file"
      docker compose --project-directory "$source_dir" -f "$compose_file" down
      containers_down=1

      log "Creating archive $archive_path"
      tar \
        --create \
        --zstd \
        --file "$tmp_archive" \
        --acls \
        --xattrs \
        --numeric-owner \
        --preserve-permissions \
        --directory "$(dirname "$source_dir")" \
        "$(basename "$source_dir")"

      mv "$tmp_archive" "$archive_path"
      tmp_archive=""

      log "Starting containers"
      docker compose --project-directory "$source_dir" -f "$compose_file" up -d
      containers_down=0

      ensure_remote_dir "$remote_base_dir"
      ensure_remote_dir "$remote_host_dir"

      log "Uploading $archive_path to Filen at $remote_host_dir"
      filen_cmd upload "$archive_path" "$remote_host_dir"

      log "Cleaning up local archive directory $archive_dir"
      find "$archive_dir" -mindepth 1 -maxdepth 1 -type f -delete
      find "$archive_dir" -mindepth 1 -maxdepth 1 -type d -empty -delete

      log "Backup finished"
    '';
  };

  restoreScript = pkgs.writeShellApplication {
    name = "docker-filen-restore";
    runtimeInputs = with pkgs; [
      coreutils
      filen-cli
      findutils
      gnutar
      gnugrep
      zstd
    ];
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      source_dir=${lib.escapeShellArg sourceDir}
      archive_dir=${lib.escapeShellArg archiveDir}
      filen_data_dir=${lib.escapeShellArg filenDataDir}
      environment_file=${lib.escapeShellArg environmentFile}
      remote_host_dir=${lib.escapeShellArg remoteHostDir}
      archive_prefix=${lib.escapeShellArg hostConfig.hostName}

      tmp_archive=""

      log() {
        printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
      }

      cleanup() {
        local status=$?

        if [[ -n "$tmp_archive" && -f "$tmp_archive" ]]; then
          rm -f "$tmp_archive"
        fi

        exit "$status"
      }
      trap cleanup EXIT

      require_filen_auth() {
        if [[ -n "''${FILEN_EMAIL:-}" && -z "''${FILEN_PASSWORD:-}" ]]; then
          log "FILEN_EMAIL is set but FILEN_PASSWORD is missing in $environment_file"
          exit 1
        fi

        if [[ -z "''${FILEN_EMAIL:-}" && ! -f "$filen_data_dir/.filen-cli-auth-config" ]]; then
          log "Missing Filen credentials. Put .filen-cli-auth-config in $filen_data_dir or set FILEN_EMAIL/FILEN_PASSWORD in $environment_file"
          exit 1
        fi
      }

      filen_cmd() {
        filen --skip-update "$@"
      }

      usage() {
        cat <<EOF
      Usage: docker-filen-restore <archive-name|latest>

      Downloads a backup archive from $remote_host_dir and extracts it into $(dirname "$source_dir").
      This command does not stop or start containers.
      EOF
      }

      resolve_archive_name() {
        if [[ $# -eq 0 || "$1" == "latest" ]]; then
          filen_cmd --json ls -l "$remote_host_dir" \
            | grep -o "name: '[^']*'" \
            | sed "s/^name: '//; s/'$//" \
            | grep "^$archive_prefix-.*\\.tar\\.zst$" \
            | sort \
            | tail -n 1
          return
        fi

        printf '%s\n' "$1"
      }

      if [[ $# -gt 1 ]]; then
        usage >&2
        exit 1
      fi

      mkdir -p "$archive_dir" "$filen_data_dir"
      export FILEN_CLI_DATA_DIR="$filen_data_dir"
      require_filen_auth

      archive_name="$(resolve_archive_name "$@")"
      if [[ -z "$archive_name" ]]; then
        log "Could not find a matching backup archive in $remote_host_dir"
        exit 1
      fi

      remote_archive_path="$remote_host_dir/$archive_name"
      tmp_archive="$archive_dir/$archive_name"

      log "Downloading $remote_archive_path"
      filen_cmd download "$remote_archive_path" "$tmp_archive"

      if [[ ! -f "$tmp_archive" ]]; then
        log "Download failed: $tmp_archive was not created"
        exit 1
      fi

      log "Extracting $tmp_archive into $(dirname "$source_dir")"
      tar \
        --extract \
        --zstd \
        --file "$tmp_archive" \
        --acls \
        --xattrs \
        --numeric-owner \
        --preserve-permissions \
        --directory "$(dirname "$source_dir")"

      log "Restore finished. Containers were not started."
    '';
  };
in
lib.mkIf enabled {
  environment.systemPackages = [
    backupScript
    restoreScript
    pkgs.filen-cli
  ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
    "d ${archiveDir} 0700 root root -"
    "d ${filenDataDir} 0700 root root -"
  ];

  systemd.services.${serviceName} = {
    description = "Back up ${sourceDir} to Filen";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      FILEN_CLI_DATA_DIR = filenDataDir;
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe backupScript;
      EnvironmentFile = [ "-${environmentFile}" ];
      Nice = 10;
      IOSchedulingClass = "best-effort";
      IOSchedulingPriority = 7;
      UMask = "0077";
      WorkingDirectory = stateDir;
    };
  };

  systemd.timers.${serviceName} = {
    description = "Run the Docker Filen backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule;
      Persistent = persistent;
      Unit = "${serviceName}.service";
    };
  };
}
