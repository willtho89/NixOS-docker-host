{ lib, config, hostConfig, ... }:

let
  cfg = hostConfig.composeStack or { };
  enabled = (cfg.enable or false) && (cfg.useSopsSecrets or false);
  dockerLayout = hostConfig.dockerLayout or { };
  projectDir = cfg.projectDir or (dockerLayout.rootDir or "/srv/docker");
  secretFile = ../secrets + "/${hostConfig.hostName}.yaml";
  adguardConfigTemplate = builtins.replaceStrings
    [
      "__ADGUARD_ADMIN_PASSWORD_HASH__"
      "__ADGUARD_ADMIN_USERNAME__"
      "__DOMAIN__"
      "__ADGUARD_REWRITES__"
    ]
    [
      config.sops.placeholder."compose-adguard-admin-password-hash"
      config.sops.placeholder."compose-adguard-admin-username"
      config.sops.placeholder."compose-domain"
      config.sops.placeholder."compose-adguard-rewrites"
    ]
    (builtins.readFile ../compose-stack/apps/adguard/config/AdGuardHome.yaml);
  composeProjectEnvTemplate = builtins.replaceStrings
    [
      "DOCKER_DIR=/srv/docker"
      "AIOSTREAMS_AUTH_ADMINS=REDACTED_USE_SOPS"
      "ADMIN_PASSWORD=REDACTED_USE_SOPS"
      "ADMIN_USERNAME=REDACTED_USE_SOPS"
      "AIOSTREAMS_AUTH=REDACTED_USE_SOPS"
      "AIOSTREAMS_SECRET_KEY=REDACTED_USE_SOPS"
      "AIOMETADATA_ADMIN_KEY=REDACTED_USE_SOPS"
      "AUTHELIA_JWT_SECRET=REDACTED_USE_SOPS"
      "AUTHELIA_SESSION_SECRET=REDACTED_USE_SOPS"
      "AUTHELIA_STORAGE_ENCRYPTION_KEY=REDACTED_USE_SOPS"
      "CACHE_WARMUP_UUID=REDACTED_USE_SOPS"
      "CACHE_WARMUP_UUIDS=REDACTED_USE_SOPS"
      "CF_API_TOKEN=REDACTED_USE_SOPS"
      "COMET_DEBRIDIO_API_KEY=REDACTED_USE_SOPS"
      "COMET_TORBOX_API_KEY=REDACTED_USE_SOPS"
      "DASHBOARD_ADMIN_PASSWORD=REDACTED_USE_SOPS"
      "DOMAIN=__DOMAIN__"
      "FANART_API_KEY=REDACTED_USE_SOPS"
      "JACKETT_API_KEY=REDACTED_USE_SOPS"
      "LETSENCRYPT_EMAIL=REDACTED_USE_SOPS"
      "LIBRARYSYNC_ADMIN_API_KEY=REDACTED_USE_SOPS"
      "LIBRARYSYNC_ANILIST_CLIENT_ID=REDACTED_USE_SOPS"
      "LIBRARYSYNC_ANILIST_CLIENT_SECRET=REDACTED_USE_SOPS"
      "LIBRARYSYNC_POSTGRES_PASSWORD=REDACTED_USE_SOPS"
      "LIBRARYSYNC_SECRET_KEY=REDACTED_USE_SOPS"
      "LIBRARYSYNC_SIMKL_CLIENT_ID=REDACTED_USE_SOPS"
      "LIBRARYSYNC_SIMKL_CLIENT_SECRET=REDACTED_USE_SOPS"
      "LIBRARYSYNC_TRAKT_CLIENT_ID=REDACTED_USE_SOPS"
      "LIBRARYSYNC_TRAKT_CLIENT_SECRET=REDACTED_USE_SOPS"
      "MEDIAFLOW_API_PASSWORD=REDACTED_USE_SOPS"
      "REAL_DEBRID_API_KEY=REDACTED_USE_SOPS"
      "RPDB_API_KEY=REDACTED_USE_SOPS"
      "STREMTHRU_GITHUB_TOKEN=REDACTED_USE_SOPS"
      "STREMTHRU_GITHUB_USER=REDACTED_USE_SOPS"
      "STREMTHRU_PROXY_AUTH=REDACTED_USE_SOPS"
      "SYNCRIBULLET_PRIVATE_ENCRYPTION_KEY=REDACTED_USE_SOPS"
      "SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_ID=REDACTED_USE_SOPS"
      "SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_SECRET=REDACTED_USE_SOPS"
      "TMDB_ACCESS_TOKEN=REDACTED_USE_SOPS"
      "TMDB_API_KEY=REDACTED_USE_SOPS"
      "TRAKT_CLIENT_ID=REDACTED_USE_SOPS"
      "TRAKT_CLIENT_SECRET=REDACTED_USE_SOPS"
      "TRUSTED_UUIDS=REDACTED_USE_SOPS"
      "TVDB_API_KEY=REDACTED_USE_SOPS"
    ]
    [
      "DOCKER_DIR=${projectDir}"
      "AIOSTREAMS_AUTH_ADMINS=${config.sops.placeholder."compose-aiostreams-auth-admins"}"
      "ADMIN_PASSWORD=${config.sops.placeholder."compose-wg-easy-admin-password"}"
      "ADMIN_USERNAME=${config.sops.placeholder."compose-wg-easy-admin-username"}"
      "AIOSTREAMS_AUTH=${config.sops.placeholder."compose-aiostreams-auth"}"
      "AIOSTREAMS_SECRET_KEY=${config.sops.placeholder."compose-aiostreams-secret-key"}"
      "AIOMETADATA_ADMIN_KEY=${config.sops.placeholder."compose-aiometadata-admin-key"}"
      "AUTHELIA_JWT_SECRET=${config.sops.placeholder."authelia-jwt-secret"}"
      "AUTHELIA_SESSION_SECRET=${config.sops.placeholder."compose-authelia-session-secret"}"
      "AUTHELIA_STORAGE_ENCRYPTION_KEY=${config.sops.placeholder."authelia-storage-encryption-key"}"
      "CACHE_WARMUP_UUID=${config.sops.placeholder."compose-aiometadata-cache-warmup-uuid"}"
      "CACHE_WARMUP_UUIDS=${config.sops.placeholder."compose-aiometadata-cache-warmup-uuid"}"
      "CF_API_TOKEN=${config.sops.placeholder."traefik-cloudflare-dns-api-token"}"
      "COMET_DEBRIDIO_API_KEY=${config.sops.placeholder."compose-comet-debridio-api-key"}"
      "COMET_TORBOX_API_KEY=${config.sops.placeholder."compose-comet-torbox-api-key"}"
      "DASHBOARD_ADMIN_PASSWORD=${config.sops.placeholder."compose-dashboard-admin-password"}"
      "DOMAIN=${config.sops.placeholder."compose-domain"}"
      "FANART_API_KEY=${config.sops.placeholder."compose-fanart-api-key"}"
      "JACKETT_API_KEY=${config.sops.placeholder."compose-jackett-api-key"}"
      "LETSENCRYPT_EMAIL=${config.sops.placeholder."compose-letsencrypt-email"}"
      "LIBRARYSYNC_ADMIN_API_KEY=${config.sops.placeholder."compose-librarysync-admin-api-key"}"
      "LIBRARYSYNC_ANILIST_CLIENT_ID=${config.sops.placeholder."compose-librarysync-anilist-client-id"}"
      "LIBRARYSYNC_ANILIST_CLIENT_SECRET=${config.sops.placeholder."compose-librarysync-anilist-client-secret"}"
      "LIBRARYSYNC_POSTGRES_PASSWORD=${config.sops.placeholder."compose-librarysync-postgres-password"}"
      "LIBRARYSYNC_SECRET_KEY=${config.sops.placeholder."compose-librarysync-secret-key"}"
      "LIBRARYSYNC_SIMKL_CLIENT_ID=${config.sops.placeholder."compose-librarysync-simkl-client-id"}"
      "LIBRARYSYNC_SIMKL_CLIENT_SECRET=${config.sops.placeholder."compose-librarysync-simkl-client-secret"}"
      "LIBRARYSYNC_TRAKT_CLIENT_ID=${config.sops.placeholder."compose-librarysync-trakt-client-id"}"
      "LIBRARYSYNC_TRAKT_CLIENT_SECRET=${config.sops.placeholder."compose-librarysync-trakt-client-secret"}"
      "MEDIAFLOW_API_PASSWORD=${config.sops.placeholder."compose-mediaflow-api-password"}"
      "REAL_DEBRID_API_KEY=${config.sops.placeholder."compose-real-debrid-api-key"}"
      "RPDB_API_KEY=${config.sops.placeholder."compose-rpdb-api-key"}"
      "STREMTHRU_GITHUB_TOKEN=${config.sops.placeholder."compose-stremthru-github-token"}"
      "STREMTHRU_GITHUB_USER=${config.sops.placeholder."compose-stremthru-github-user"}"
      "STREMTHRU_PROXY_AUTH=${config.sops.placeholder."compose-stremthru-proxy-auth"}"
      "SYNCRIBULLET_PRIVATE_ENCRYPTION_KEY=${config.sops.placeholder."compose-syncribullet-private-encryption-key"}"
      "SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_ID=${config.sops.placeholder."compose-syncribullet-simkl-client-id"}"
      "SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_SECRET=${config.sops.placeholder."compose-syncribullet-simkl-client-secret"}"
      "TMDB_ACCESS_TOKEN=${config.sops.placeholder."compose-tmdb-access-token"}"
      "TMDB_API_KEY=${config.sops.placeholder."compose-tmdb-api-key"}"
      "TRAKT_CLIENT_ID=${config.sops.placeholder."compose-trakt-client-id"}"
      "TRAKT_CLIENT_SECRET=${config.sops.placeholder."compose-trakt-client-secret"}"
      "TRUSTED_UUIDS=${config.sops.placeholder."compose-aiostreams-trusted-uuids"}"
      "TVDB_API_KEY=${config.sops.placeholder."compose-tvdb-api-key"}"
    ]
    (builtins.readFile ../compose-stack/.env);
in
{
  assertions = [
    {
      assertion = !enabled || builtins.pathExists secretFile;
      message = "Missing tracked sops file at ${toString secretFile}.";
    }
  ];

  sops = lib.mkIf enabled {
    defaultSopsFile = secretFile;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "traefik-cloudflare-dns-api-token" = { };
      "authelia-users-yaml" = { };
      "authelia-jwt-secret" = { };
      "authelia-storage-encryption-key" = { };
      "compose-adguard-admin-password" = { };
      "compose-adguard-admin-password-hash" = { };
      "compose-adguard-admin-username" = { };
      "compose-adguard-rewrites" = { };
      "compose-aiometadata-admin-key" = { };
      "compose-aiometadata-cache-warmup-uuid" = { };
      "compose-aiostreams-auth" = { };
      "compose-aiostreams-auth-admins" = { };
      "compose-aiostreams-secret-key" = { };
      "compose-aiostreams-trusted-uuids" = { };
      "compose-authelia-session-secret" = { };
      "compose-comet-debridio-api-key" = { };
      "compose-comet-torbox-api-key" = { };
      "compose-dashboard-admin-password" = { };
      "compose-domain" = { };
      "compose-fanart-api-key" = { };
      "compose-jackett-api-key" = { };
      "compose-letsencrypt-email" = { };
      "compose-librarysync-admin-api-key" = { };
      "compose-librarysync-anilist-client-id" = { };
      "compose-librarysync-anilist-client-secret" = { };
      "compose-librarysync-postgres-password" = { };
      "compose-librarysync-secret-key" = { };
      "compose-librarysync-simkl-client-id" = { };
      "compose-librarysync-simkl-client-secret" = { };
      "compose-librarysync-trakt-client-id" = { };
      "compose-librarysync-trakt-client-secret" = { };
      "compose-mediaflow-api-password" = { };
      "compose-real-debrid-api-key" = { };
      "compose-rpdb-api-key" = { };
      "compose-stremthru-github-token" = { };
      "compose-stremthru-github-user" = { };
      "compose-stremthru-proxy-auth" = { };
      "compose-syncribullet-private-encryption-key" = { };
      "compose-syncribullet-simkl-client-id" = { };
      "compose-syncribullet-simkl-client-secret" = { };
      "compose-tmdb-access-token" = { };
      "compose-tmdb-api-key" = { };
      "compose-trakt-client-id" = { };
      "compose-trakt-client-secret" = { };
      "compose-tvdb-api-key" = { };
      "compose-wg-easy-admin-password" = { };
      "compose-wg-easy-admin-username" = { };
    };

    templates = {
      "docker-authelia-users.yml" = {
        mode = "0400";
        content = ''
          ${config.sops.placeholder."authelia-users-yaml"}
        '';
      };

      "docker-adguard-config.yml" = {
        mode = "0400";
        content = adguardConfigTemplate;
      };

      "docker-compose-project.env" = {
        mode = "0400";
        content = composeProjectEnvTemplate;
      };

      "docker-compose-secrets.env" = {
        mode = "0400";
        content = ''
          ADMIN_PASSWORD=${config.sops.placeholder."compose-wg-easy-admin-password"}
          ADMIN_USERNAME=${config.sops.placeholder."compose-wg-easy-admin-username"}
          AIOMETADATA_ADMIN_KEY=${config.sops.placeholder."compose-aiometadata-admin-key"}
          AIOSTREAMS_AUTH=${config.sops.placeholder."compose-aiostreams-auth"}
          AIOSTREAMS_AUTH_ADMINS=${config.sops.placeholder."compose-aiostreams-auth-admins"}
          AIOSTREAMS_SECRET_KEY=${config.sops.placeholder."compose-aiostreams-secret-key"}
          AUTHELIA_JWT_SECRET=${config.sops.placeholder."authelia-jwt-secret"}
          AUTHELIA_SESSION_SECRET=${config.sops.placeholder."compose-authelia-session-secret"}
          AUTHELIA_STORAGE_ENCRYPTION_KEY=${config.sops.placeholder."authelia-storage-encryption-key"}
          CACHE_WARMUP_UUID=${config.sops.placeholder."compose-aiometadata-cache-warmup-uuid"}
          CACHE_WARMUP_UUIDS=${config.sops.placeholder."compose-aiometadata-cache-warmup-uuid"}
          CF_API_TOKEN=${config.sops.placeholder."traefik-cloudflare-dns-api-token"}
          COMET_DEBRIDIO_API_KEY=${config.sops.placeholder."compose-comet-debridio-api-key"}
          COMET_TORBOX_API_KEY=${config.sops.placeholder."compose-comet-torbox-api-key"}
          DASHBOARD_ADMIN_PASSWORD=${config.sops.placeholder."compose-dashboard-admin-password"}
          DOMAIN=${config.sops.placeholder."compose-domain"}
          FANART_API_KEY=${config.sops.placeholder."compose-fanart-api-key"}
          JACKETT_API_KEY=${config.sops.placeholder."compose-jackett-api-key"}
          LETSENCRYPT_EMAIL=${config.sops.placeholder."compose-letsencrypt-email"}
          LIBRARYSYNC_ADMIN_API_KEY=${config.sops.placeholder."compose-librarysync-admin-api-key"}
          LIBRARYSYNC_ANILIST_CLIENT_ID=${config.sops.placeholder."compose-librarysync-anilist-client-id"}
          LIBRARYSYNC_ANILIST_CLIENT_SECRET=${config.sops.placeholder."compose-librarysync-anilist-client-secret"}
          LIBRARYSYNC_POSTGRES_PASSWORD=${config.sops.placeholder."compose-librarysync-postgres-password"}
          LIBRARYSYNC_SECRET_KEY=${config.sops.placeholder."compose-librarysync-secret-key"}
          LIBRARYSYNC_SIMKL_CLIENT_ID=${config.sops.placeholder."compose-librarysync-simkl-client-id"}
          LIBRARYSYNC_SIMKL_CLIENT_SECRET=${config.sops.placeholder."compose-librarysync-simkl-client-secret"}
          LIBRARYSYNC_TRAKT_CLIENT_ID=${config.sops.placeholder."compose-librarysync-trakt-client-id"}
          LIBRARYSYNC_TRAKT_CLIENT_SECRET=${config.sops.placeholder."compose-librarysync-trakt-client-secret"}
          MEDIAFLOW_API_PASSWORD=${config.sops.placeholder."compose-mediaflow-api-password"}
          REAL_DEBRID_API_KEY=${config.sops.placeholder."compose-real-debrid-api-key"}
          RPDB_API_KEY=${config.sops.placeholder."compose-rpdb-api-key"}
          STREMTHRU_GITHUB_TOKEN=${config.sops.placeholder."compose-stremthru-github-token"}
          STREMTHRU_GITHUB_USER=${config.sops.placeholder."compose-stremthru-github-user"}
          STREMTHRU_PROXY_AUTH=${config.sops.placeholder."compose-stremthru-proxy-auth"}
          SYNCRIBULLET_PRIVATE_ENCRYPTION_KEY=${config.sops.placeholder."compose-syncribullet-private-encryption-key"}
          SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_ID=${config.sops.placeholder."compose-syncribullet-simkl-client-id"}
          SYNCRIBULLET_PRIVATE_SIMKL_CLIENT_SECRET=${config.sops.placeholder."compose-syncribullet-simkl-client-secret"}
          TMDB_ACCESS_TOKEN=${config.sops.placeholder."compose-tmdb-access-token"}
          TMDB_API_KEY=${config.sops.placeholder."compose-tmdb-api-key"}
          TRAKT_CLIENT_ID=${config.sops.placeholder."compose-trakt-client-id"}
          TRAKT_CLIENT_SECRET=${config.sops.placeholder."compose-trakt-client-secret"}
          TRUSTED_UUIDS=${config.sops.placeholder."compose-aiostreams-trusted-uuids"}
          TVDB_API_KEY=${config.sops.placeholder."compose-tvdb-api-key"}
        '';
      };
    };
  };
}
