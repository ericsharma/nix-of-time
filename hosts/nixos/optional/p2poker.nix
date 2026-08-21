{
  config,
  pkgs,
  p2poker,
  ...
}:

let
  # Single pnpm.fetchDeps for both derivations — they share one lockfile and one
  # node_modules tree, so one hash. Keeps the SPA and relay builds in lockstep
  # across `nix flake update p2poker`.
  #
  # First build will fail with a hash mismatch. Copy the "got:" hash printed by
  # Nix into `hash` below and rebuild.
  pnpmDeps = pkgs.pnpm.fetchDeps {
    pname = "p2poker";
    version = "0.0.0";
    src = p2poker;
    fetcherVersion = 2;
    hash = "sha256-cpLf2QABO868fdQ1S7l15+9z4Q9oeM4qAuq+V04IPo4=";
  };

  spa = pkgs.stdenv.mkDerivation {
    pname = "p2poker-spa";
    version = "0.0.0";
    src = p2poker;
    inherit pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.pnpm
      pkgs.pnpm.configHook
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
    pname = "p2poker-server";
    version = "0.0.0";
    src = p2poker;
    inherit pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.pnpm
      pkgs.pnpm.configHook
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
      cp server/dist/index.mjs $out/share/p2poker-server.mjs
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/p2poker-server \
        --add-flags $out/share/p2poker-server.mjs
      runHook postInstall
    '';
  };
in
{
  # ── p2poker (peer-to-peer Texas Hold'em) ────────────────────────────────────
  # Pangolin/Newt → 127.0.0.1:4207 → nginx vhost.
  # nginx serves the static SPA at /, reverse-proxies /relay and /api/* to the
  # Hono ws-relay server at 127.0.0.1:4217.
  #
  # Relay-only: the server brokers the WebRTC handshake and mints TURN
  # credentials, and nothing else — no database, no auth, no game state. Once
  # peers connect, all game data flows directly peer-to-peer and never touches
  # this host (a TURN relay only forwards encrypted DTLS, so even a relayed
  # table is opaque to Cloudflare).

  # Cloudflare Realtime TURN credentials (TURN_TOKEN_ID, TURN_API_TOKEN_ID).
  # The server mints short-lived ICE credentials from these on
  # POST /api/turn-credentials so the API token never reaches the browser.
  # Same Cloudflare TURN key PiroueSync uses — one key, two apps.
  sops.secrets."p2poker/env" = { };

  systemd.services.p2poker-server = {
    description = "p2poker ws-relay server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      HONO_PORT = "4217";
      NODE_ENV = "production";
    };

    serviceConfig = {
      ExecStart = "${server}/bin/p2poker-server";
      Restart = "on-failure";
      RestartSec = "5s";

      # systemd reads this as root before dropping to the DynamicUser, so the
      # default 0400 root-owned sops secret is readable here.
      EnvironmentFile = config.sops.secrets."p2poker/env".path;

      # No state; the only secret is the TURN minting token, which is read
      # from the environment file above and never written to disk by the app.
      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."poker.ericsharma.xyz" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 4207;
        }
      ];
      root = "${spa}";
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:4217";
        proxyWebsockets = true;
      };
      locations."/relay" = {
        proxyPass = "http://127.0.0.1:4217";
        proxyWebsockets = true;
        # Trystero ws-relay sockets sit idle once peers complete their WebRTC
        # handshake (data path is P2P). nginx's default 60s proxy_read_timeout
        # would tear them down; the server pings every 25s, this gives headroom.
        extraConfig = ''
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
      };
    };
  };
}
