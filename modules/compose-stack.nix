{ lib, pkgs, config, hostConfig, ... }:

let
  cfg = hostConfig.composeStack or { };
  enabled = cfg.enable or false;
  serviceName = cfg.serviceName or "docker-compose-apps";
  dockerLayout = hostConfig.dockerLayout or { };
  dockerRootDir = dockerLayout.rootDir or "/srv/docker";
  dockerDataUser = dockerLayout.dataUser or { };
  dockerDataUserName = dockerDataUser.name or "dockerapps";
  dockerDataGroup = dockerDataUser.group or "docker-data";
  projectDir = cfg.projectDir or dockerRootDir;
  composeFile = cfg.composeFile or "${projectDir}/compose.yaml";
  sourceDir = cfg.sourceDir or ../compose-example;
  managedSourceDir = "${sourceDir}/";
  syncFiles = cfg.syncFiles or false;
  syncServiceName = "${serviceName}-sync";
  ensureServiceName = "${serviceName}-ensure";
  useSopsSecrets = cfg.useSopsSecrets or false;
  baseEnvironmentFiles =
    lib.optional useSopsSecrets config.sops.templates."docker-compose-secrets.env".path;
  autheliaUsersTemplate =
    lib.optionalString useSopsSecrets config.sops.templates."docker-authelia-users.yml".path;
  adguardConfigTemplate =
    lib.optionalString useSopsSecrets config.sops.templates."docker-adguard-config.yml".path;
  composeProjectEnvTemplatePlain = pkgs.writeText "docker-compose-project.env" (builtins.replaceStrings
    [ "DOCKER_DIR=/srv/docker" "DOMAIN=__DOMAIN__" ]
    [ "DOCKER_DIR=${projectDir}" "DOMAIN=example.com" ]
    (builtins.readFile ../compose-example/.env));
  composeProjectEnvTemplate =
    if useSopsSecrets then
      config.sops.templates."docker-compose-project.env".path
    else
      composeProjectEnvTemplatePlain;
  environmentFiles = baseEnvironmentFiles ++ (cfg.environmentFiles or [ ]);
  environment = cfg.environment or { };
  environmentList = lib.mapAttrsToList (name: value: "${name}=${toString value}") environment;
  environmentExportScript = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg (toString value)}") environment
  );
  environmentFileSourceScript = lib.concatMapStringsSep "\n" (file: ''
    if [ -f ${lib.escapeShellArg file} ]; then
      set -a
      # shellcheck source=/dev/null
      . ${lib.escapeShellArg file}
      set +a
    fi
  '') environmentFiles;
  syncScript = pkgs.writeShellApplication {
    name = syncServiceName;
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      rsync
    ];
    text = ''
      set -euo pipefail

      legacy_adguard_conf=${lib.escapeShellArg "${projectDir}/apps/adguard/config"}
      managed_adguard_conf=${lib.escapeShellArg "${projectDir}/data/adguard/conf"}

      if [ -d "$legacy_adguard_conf" ] && [ ! -e "$managed_adguard_conf/AdGuardHome.yaml" ]; then
        mkdir -p "$managed_adguard_conf"
        ${pkgs.rsync}/bin/rsync \
          -a \
          "$legacy_adguard_conf/" \
          "$managed_adguard_conf/"
      fi

      mkdir -p ${lib.escapeShellArg projectDir}
      ${pkgs.rsync}/bin/rsync \
        -a \
        --delete \
        --exclude=/data/ \
        --chown=${dockerDataUserName}:${dockerDataGroup} \
        ${lib.escapeShellArg managedSourceDir} \
        ${lib.escapeShellArg "${projectDir}/"}

      mkdir -p "$managed_adguard_conf"
      ${lib.optionalString useSopsSecrets ''
        if [ ! -f "$managed_adguard_conf/AdGuardHome.yaml" ]; then
          install \
            -m 0640 \
            -o ${dockerDataUserName} \
            -g ${dockerDataGroup} \
            ${lib.escapeShellArg adguardConfigTemplate} \
            "$managed_adguard_conf/AdGuardHome.yaml"
        fi
      ''}
      ${lib.optionalString (!useSopsSecrets) ''
        tracked_adguard_config=${lib.escapeShellArg "${projectDir}/apps/adguard/config/AdGuardHome.yaml"}
        if [ -f "$tracked_adguard_config" ] && [ ! -f "$managed_adguard_conf/AdGuardHome.yaml" ]; then
          install \
            -m 0640 \
            -o ${dockerDataUserName} \
            -g ${dockerDataGroup} \
            "$tracked_adguard_config" \
            "$managed_adguard_conf/AdGuardHome.yaml"
        fi
      ''}

      if [ -d ${lib.escapeShellArg "${projectDir}/apps/authelia/config"} ]; then
        chmod 0750 ${lib.escapeShellArg "${projectDir}/apps/authelia/config"}
        find ${lib.escapeShellArg "${projectDir}/apps/authelia/config"} -mindepth 1 -type d -exec chmod 0750 {} +
        find ${lib.escapeShellArg "${projectDir}/apps/authelia/config"} -type f -exec chmod 0640 {} +
        if [ -f ${lib.escapeShellArg "${projectDir}/apps/authelia/config/notification.txt"} ]; then
          chmod 0660 ${lib.escapeShellArg "${projectDir}/apps/authelia/config/notification.txt"}
        fi
      fi

      install \
        -m 0640 \
        -o ${dockerDataUserName} \
        -g ${dockerDataGroup} \
        ${lib.escapeShellArg composeProjectEnvTemplate} \
        ${lib.escapeShellArg "${projectDir}/.env"}

      ${lib.optionalString useSopsSecrets ''
        mkdir -p ${lib.escapeShellArg "${projectDir}/apps/authelia/config"}
        install \
          -m 0640 \
          -o ${dockerDataUserName} \
          -g ${dockerDataGroup} \
          ${lib.escapeShellArg autheliaUsersTemplate} \
          ${lib.escapeShellArg "${projectDir}/apps/authelia/config/users.yml"}
      ''}
    '';
  };
  ensureScript = pkgs.writeShellApplication {
    name = ensureServiceName;
    runtimeInputs = with pkgs; [
      coreutils
      docker
      jq
    ];
    text = ''
      set -euo pipefail

      ${environmentExportScript}
      ${environmentFileSourceScript}

      if [ ! -f ${lib.escapeShellArg composeFile} ]; then
        exit 0
      fi

      mapfile -t services < <(
        ${pkgs.docker}/bin/docker compose \
          --project-directory ${lib.escapeShellArg projectDir} \
          -f ${lib.escapeShellArg composeFile} \
          config --services
      )

      if [ "''${#services[@]}" -eq 0 ]; then
        exit 0
      fi

      ps_json="$(
        ${pkgs.docker}/bin/docker compose \
          --project-directory ${lib.escapeShellArg projectDir} \
          -f ${lib.escapeShellArg composeFile} \
          ps --all --format json 2>/dev/null || printf '[]\n'
      )"

      if [ -z "$ps_json" ]; then
        ps_json='[]'
      fi

      needs_up=0
      for service in "''${services[@]}"; do
        if ! printf '%s\n' "$ps_json" | ${pkgs.jq}/bin/jq -e --arg service "$service" \
          'if type == "array" then any(.[]; .Service == $service and .State == "running" and ((.Health // "") != "unhealthy")) else false end' \
          >/dev/null; then
          needs_up=1
          break
        fi
      done

      if [ "$needs_up" -eq 1 ]; then
        ${lib.optionalString syncFiles ''
          ${syncScript}/bin/${syncServiceName}
        ''}
        ${pkgs.docker}/bin/docker compose \
          --project-directory ${lib.escapeShellArg projectDir} \
          -f ${lib.escapeShellArg composeFile} \
          up -d --remove-orphans
      fi
    '';
  };
in
{
  system.activationScripts.${ensureServiceName} = lib.mkIf enabled {
    deps = [ "users" "groups" "etc" ];
    text = ''
      ${lib.optionalString useSopsSecrets ''
        if [ -d ${lib.escapeShellArg projectDir} ]; then
          install \
            -m 0640 \
            -o ${dockerDataUserName} \
            -g ${dockerDataGroup} \
            ${lib.escapeShellArg composeProjectEnvTemplate} \
            ${lib.escapeShellArg "${projectDir}/.env"}
        fi
      ''}

      ${lib.optionalString (!useSopsSecrets) ''
        if [ -d ${lib.escapeShellArg projectDir} ]; then
          install \
            -m 0640 \
            -o ${dockerDataUserName} \
            -g ${dockerDataGroup} \
            ${lib.escapeShellArg composeProjectEnvTemplate} \
            ${lib.escapeShellArg "${projectDir}/.env"}
        fi
      ''}

      if ${pkgs.systemd}/bin/systemctl --quiet is-active docker.service; then
        ${ensureScript}/bin/${ensureServiceName}
      fi
    '';
  };

  systemd.services.${syncServiceName} = lib.mkIf (enabled && syncFiles) {
    description = "Sync managed Docker Compose files";
    after = [
      "local-fs.target"
    ];
    before = [ "${serviceName}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${syncScript}/bin/${syncServiceName}";
    };
  };

  systemd.services.${serviceName} = lib.mkIf enabled {
    description = "Managed Docker Compose stack";
    reloadTriggers = [ syncScript ];
    after =
      [
        "docker.service"
        "network-online.target"
      ]
      ++ lib.optional syncFiles "${syncServiceName}.service"
      ++ (cfg.after or [ ]);
    wants =
      [
        "docker.service"
        "network-online.target"
      ]
      ++ lib.optional syncFiles "${syncServiceName}.service"
      ++ (cfg.wants or [ ]);
    wantedBy = cfg.wantedBy or [ "multi-user.target" ];
    partOf = [ "docker.service" ];
    path = with pkgs; [
      coreutils
      docker
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = projectDir;
      Environment = environmentList;
      EnvironmentFile = environmentFiles;
      ExecStartPre = "${pkgs.coreutils}/bin/test -f ${composeFile}";
      ExecStart = "${pkgs.docker}/bin/docker compose --project-directory ${projectDir} -f ${composeFile} up -d --remove-orphans";
      ExecStop = "${pkgs.docker}/bin/docker compose --project-directory ${projectDir} -f ${composeFile} down";
      ExecReload = [
        "${syncScript}/bin/${syncServiceName}"
        "${pkgs.docker}/bin/docker compose --project-directory ${projectDir} -f ${composeFile} up -d --remove-orphans"
      ];
      TimeoutStartSec = "15min";
      TimeoutStopSec = "15min";
    };
  };
}
