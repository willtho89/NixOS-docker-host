{ lib, hostConfig }:

let
  cfg = hostConfig.composeStack or { };
  envOverride = cfg.environment or { };
  dockerLayout = hostConfig.dockerLayout or { };
  rootDir = cfg.projectDir or (dockerLayout.rootDir or "/srv/docker");
  appsDir = dockerLayout.appsDir or "${rootDir}/apps";
  dataDir = dockerLayout.dataDir or "${rootDir}/data";
  dataUser = dockerLayout.dataUser or { };
  dataUserName = dataUser.name or "dockerapps";
  dataGroup = dataUser.group or "docker-data";
  dataUid = dataUser.uid or null;
  dataGid = dataUser.gid or null;

  stripQuotes = value:
    if lib.hasPrefix "\"" value && lib.hasSuffix "\"" value then
      builtins.substring 1 ((builtins.stringLength value) - 2) value
    else
      value;

  parseLine = line:
    let
      match = builtins.match ''^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'' line;
    in
    if match == null then
      null
    else
      lib.nameValuePair (builtins.elemAt match 0) (stripQuotes (builtins.elemAt match 1));

  rawEnv = builtins.listToAttrs (
    lib.filter (value: value != null) (
      map
        parseLine
        (
          lib.filter
            (line: line != "" && !lib.hasPrefix "#" line)
            (lib.splitString "\n" (builtins.readFile ../compose-stack/.env))
        )
    )
  );

  sourceEnv = rawEnv // lib.mapAttrs (_: value: toString value) envOverride;

  expandOnce = value:
    lib.foldl'
      (acc: name: builtins.replaceStrings [ "\${${name}}" ] [ (sourceEnv.${name} or "") ] acc)
      (toString value)
      (builtins.attrNames sourceEnv);

  expandValue = value:
    let
      first = expandOnce value;
      second = expandOnce first;
    in
    second;

  resolvedEnv = lib.mapAttrs (_: value: expandValue value) sourceEnv;

  get = name: default:
    toString (resolvedEnv.${name} or default);

  domain = get "DOMAIN" "";
  composeProjectName = get "COMPOSE_PROJECT_NAME" "aio";
  dockerNetwork = get "DOCKER_NETWORK" "${composeProjectName}_network";
  wgNetwork = "${composeProjectName}_wg";

  nonSecretEnvBase = {
    TZ = get "TZ" (hostConfig.timeZone or "UTC");
    DOCKER_DIR = rootDir;
    DOCKER_DATA_DIR = dataDir;
    DOCKER_APP_DIR = appsDir;
    PUID = if dataUid != null then toString dataUid else get "PUID" "1100";
    PGID = if dataGid != null then toString dataGid else get "PGID" "1100";
    COMPOSE_PROFILES = get "COMPOSE_PROFILES" "";
    DOMAIN = domain;
    LETSENCRYPT_EMAIL = get "LETSENCRYPT_EMAIL" "";
    TRUSTED_IPS = get "TRUSTED_IPS" "";
    LE_CA_SERVER = get "LE_CA_SERVER" "https://acme-v02.api.letsencrypt.org/directory";
    AUTHELIA_WEBAUTHN_DISPLAY_NAME = get "AUTHELIA_WEBAUTHN_DISPLAY_NAME" "Authelia";
    ADGUARD_PORT = get "ADGUARD_PORT" "80";
    COMPOSE_PROJECT_NAME = composeProjectName;
    COMPOSE_REMOVE_ORPHANS = get "COMPOSE_REMOVE_ORPHANS" "true";
    COMPOSE_BAKE = get "COMPOSE_BAKE" "true";
    COMPOSE_FILE = get "COMPOSE_FILE" "${rootDir}/compose.yaml";
    DOCKER_NETWORK = dockerNetwork;
    DOCKER_NETWORK_EXTERNAL = get "DOCKER_NETWORK_EXTERNAL" "false";
  };

  hostnames =
    let
      hostname = name: prefix: get name "${prefix}.${domain}";
    in
    {
      ADGUARD_HOSTNAME = hostname "ADGUARD_HOSTNAME" "adguard";
      AIOMETADATA_HOSTNAME = hostname "AIOMETADATA_HOSTNAME" "aiometadata";
      AIOSTREAMS_HOSTNAME = hostname "AIOSTREAMS_HOSTNAME" "aiostreams";
      AUTHELIA_HOSTNAME = hostname "AUTHELIA_HOSTNAME" "auth";
      COMET_HOSTNAME = hostname "COMET_HOSTNAME" "comet";
      JACKETTIO_HOSTNAME = hostname "JACKETTIO_HOSTNAME" "jackettio";
      JACKETT_HOSTNAME = hostname "JACKETT_HOSTNAME" "jackett";
      EASYNEWS_PLUS_HOSTNAME = hostname "EASYNEWS_PLUS_HOSTNAME" "easynews-plus-plus";
      LIBRARYSYNC_HOSTNAME = hostname "LIBRARYSYNC_HOSTNAME" "librarysync";
      LIBRESPEED_HOSTNAME = hostname "LIBRESPEED_HOSTNAME" "speedtest";
      NZBDAV_HOSTNAME = hostname "NZBDAV_HOSTNAME" "nzbdav";
      NZBHYDRA2_HOSTNAME = hostname "NZBHYDRA2_HOSTNAME" "nzbhydra2";
      STREMTHRU_HOSTNAME = hostname "STREMTHRU_HOSTNAME" "stremthru";
      SYNCRIBULLET_HOSTNAME = hostname "SYNCRIBULLET_HOSTNAME" "syncribullet";
      TRAEFIK_HOSTNAME = hostname "TRAEFIK_HOSTNAME" "traefik";
      WG_EASY_HOSTNAME = hostname "WG_EASY_HOSTNAME" "vpn";
      ZILEAN_HOSTNAME = hostname "ZILEAN_HOSTNAME" "zilean";
    };

  secretKeys = [
    "ADMIN_PASSWORD"
    "ADMIN_USERNAME"
    "AIOSTREAMS_AUTH"
    "AIOSTREAMS_SECRET_KEY"
    "AIOMETADATA_ADMIN_KEY"
    "AUTHELIA_JWT_SECRET"
    "AUTHELIA_SESSION_SECRET"
    "AUTHELIA_STORAGE_ENCRYPTION_KEY"
    "CF_API_TOKEN"
    "COMET_DEBRIDIO_API_KEY"
    "COMET_TORBOX_API_KEY"
    "DASHBOARD_ADMIN_PASSWORD"
    "FANART_API_KEY"
    "JACKETT_API_KEY"
    "LIBRARYSYNC_ADMIN_API_KEY"
    "LIBRARYSYNC_ANILIST_CLIENT_ID"
    "LIBRARYSYNC_ANILIST_CLIENT_SECRET"
    "LIBRARYSYNC_POSTGRES_PASSWORD"
    "LIBRARYSYNC_SECRET_KEY"
    "LIBRARYSYNC_SIMKL_CLIENT_ID"
    "LIBRARYSYNC_SIMKL_CLIENT_SECRET"
    "LIBRARYSYNC_TRAKT_CLIENT_ID"
    "LIBRARYSYNC_TRAKT_CLIENT_SECRET"
    "MEDIAFLOW_API_PASSWORD"
    "MEDIAFUSION_API_PASSWORD"
    "REAL_DEBRID_API_KEY"
    "RPDB_API_KEY"
    "STREMTHRU_GITHUB_TOKEN"
    "STREMTHRU_PROXY_AUTH"
    "SYNCRIBULLET_PRIVATE_ENCRYPTION_KEY"
    "SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_ID"
    "SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_SECRET"
    "TMDB_ACCESS_TOKEN"
    "TMDB_API_KEY"
    "TRAKT_CLIENT_ID"
    "TRAKT_CLIENT_SECRET"
    "TVDB_API_KEY"
  ];

  reservedKeys = builtins.attrNames nonSecretEnvBase ++ builtins.attrNames hostnames ++ secretKeys;

  passthroughEnv = lib.filterAttrs (name: _: !(lib.elem name reservedKeys)) envOverride;

  nonSecretEnv = nonSecretEnvBase // hostnames // passthroughEnv;

  renderEnvFile = secretEnv:
    let
      env = nonSecretEnv // secretEnv;
    in
    lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${toString value}") env) + "\n";

  profiles = lib.filter (name: name != "") (lib.splitString "," nonSecretEnv.COMPOSE_PROFILES);
  hasProfile = name: lib.elem name profiles || lib.elem "all" profiles;
in
{
  inherit
    appsDir
    composeProjectName
    dataDir
    dataGid
    dataGroup
    dataUid
    dataUserName
    dockerNetwork
    domain
    hasProfile
    hostnames
    nonSecretEnv
    profiles
    rawEnv
    renderEnvFile
    rootDir
    secretKeys
    wgNetwork
    ;
}
