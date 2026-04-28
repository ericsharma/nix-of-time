{ config, pkgs, pirousync, ... }:

let
  # Single pnpm.fetchDeps for both derivations — they share one lockfile and
  # one node_modules tree, so one hash. Extracting to a `let` binding keeps
  # the SPA and server builds in lockstep across `nix flake update pirousync`.
  #
  # First build will fail with a hash mismatch. Copy the "got:" hash printed
  # by Nix into `hash` below and rebuild.
  pnpmDeps = pkgs.pnpm_9.fetchDeps {
    pname          = "pirousync";
    version        = "0.0.0";
    src            = pirousync;
    fetcherVersion = 2;
    hash           = "sha256-K2D+ApgYVK2fLi5/TtwZIOpyFwcxZtm/3qg/r3Dw6Xw=";
  };

  spa = pkgs.stdenv.mkDerivation {
    pname   = "pirousync-spa";
    version = "0.0.0";
    src     = pirousync;
    inherit pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.pnpm_9
      pkgs.pnpm_9.configHook
    ];

    buildPhase = ''
      runHook preBuild
      pnpm run build:client
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  server = pkgs.stdenv.mkDerivation {
    pname   = "pirousync-server";
    version = "0.0.0";
    src     = pirousync;
    inherit pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.pnpm_9
      pkgs.pnpm_9.configHook
      pkgs.makeWrapper
    ];

    buildPhase = ''
      runHook preBuild
      pnpm run build:server
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share
      cp server/dist/index.mjs $out/share/pirousync-server.mjs
      cp -r server/drizzle $out/share/drizzle
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/pirousync-server \
        --add-flags $out/share/pirousync-server.mjs \
        --set DRIZZLE_MIGRATIONS_DIR $out/share/drizzle
      runHook postInstall
    '';
  };
in
{
  # ── PiroueSync (synchronized ballet class music player) ─────────────────────
  # Pangolin/Newt → 127.0.0.1:4203 → nginx vhost.
  # nginx serves the static SPA at /, reverse-proxies /api/* to the Hono
  # server at 127.0.0.1:4213.
  #
  # Build-time `VITE_*` values for the SPA bundle live in the repo's committed
  # .env.production. Runtime secrets (Garage credentials, AUTH_SECRET) live in
  # sops at pirousync/env and are loaded into the systemd unit via
  # EnvironmentFile.

  sops.secrets."pirousync/env" = {
    owner = "pirousync";
  };

  users.users.pirousync = {
    isSystemUser = true;
    group        = "pirousync";
    description  = "PiroueSync server";
  };
  users.groups.pirousync = {};

  services.postgresql = {
    enable          = true;
    ensureDatabases = [ "pirousync" ];
    ensureUsers = [
      {
        name                = "pirousync";
        ensureDBOwnership   = true;
        ensureClauses.login = true;
      }
    ];
  };

  systemd.services.pirousync-server = {
    description = "PiroueSync Hono server";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" "postgresql.service" ];
    requires    = [ "postgresql.service" ];

    environment = {
      # postgres.js doesn't auto-decode URL-encoded socket paths, but our
      # server/src/db/connection.ts parses the URL and hands the host in
      # cleanly, so the readable `?host=/path` form is fine here.
      DATABASE_URL = "postgres://pirousync@/pirousync?host=/run/postgresql";
      HONO_PORT    = "4213";
      BASE_URL     = "https://dance.bellewatsonstudio.com";
      NODE_ENV     = "production";
    };

    serviceConfig = {
      User             = "pirousync";
      Group            = "pirousync";
      EnvironmentFile  = config.sops.secrets."pirousync/env".path;
      ExecStart        = "${server}/bin/pirousync-server";
      Restart          = "on-failure";
      RestartSec       = "5s";

      # Hardening — same posture as other small services on this host.
      NoNewPrivileges  = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      PrivateTmp       = true;
      PrivateDevices   = true;
    };
  };

  services.nginx = {
    enable                  = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."dance.bellewatsonstudio.com" = {
      listen = [ { addr = "127.0.0.1"; port = 4203; } ];
      root   = "${spa}";
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
      locations."/api/" = {
        proxyPass       = "http://127.0.0.1:4213";
        proxyWebsockets = true;
      };
      locations."/relay" = {
        proxyPass       = "http://127.0.0.1:4213";
        proxyWebsockets = true;
        # Trystero ws-relay sockets sit idle once peers complete their WebRTC
        # handshake (data path is P2P). nginx's default 60s proxy_read_timeout
        # would tear them down, after which @trystero-p2p/ws-relay 0.24.0
        # reconnects but does not re-subscribe — making the room invisible to
        # late joiners. The server sends WS pings every 25s; this just gives
        # them headroom.
        extraConfig = ''
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
      };
    };
  };
}
