{
  pkgs,
  p2poker-native,
  ...
}:

let
  # The room directory from the p2poker repo's server/ package (its own pnpm
  # lockfile). New lockfile: set hash = lib.fakeHash, build, copy "got:".
  src = "${p2poker-native}/server";

  pnpmDeps = pkgs.pnpm.fetchDeps {
    pname = "p2poker-directory";
    version = "0.0.0";
    inherit src;
    fetcherVersion = 2;
    hash = "sha256-a0ifaYETVba+vxre24z8aC2Nbns3tsCAqnR/h0UkD4E=";
  };

  server = pkgs.stdenv.mkDerivation {
    pname = "p2poker-directory";
    version = "0.0.0";
    inherit src pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.pnpm
      pkgs.pnpm.configHook
      pkgs.makeWrapper
    ];

    buildPhase = ''
      runHook preBuild
      pnpm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share
      cp dist/index.mjs $out/share/p2poker-server.mjs
      makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/p2poker-server \
        --add-flags $out/share/p2poker-server.mjs
      runHook postInstall
    '';
  };
in
{
  # ── p2poker room directory ──────────────────────────────────────────────────
  # Pangolin/Newt → 127.0.0.1:4207 → nginx vhost → Hono ws-relay at
  # 127.0.0.1:4217 (/relay, /api/health).
  #
  # The iOS/macOS apps announce their iroh ids per room here and learn each
  # other's; all game data flows over iroh (p2poker-relay.nix) and never
  # touches this host. No state, no secrets.
  systemd.services.p2poker-server = {
    description = "p2poker room directory";
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
      # The game is the iOS/macOS app; there is no web client.
      locations."/" = {
        return = "200 'p2poker is an iOS and macOS app.\\n'";
        extraConfig = ''
          default_type text/plain;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "no-referrer" always;
        '';
      };
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:4217";
      };
      locations."/relay" = {
        proxyPass = "http://127.0.0.1:4217";
        proxyWebsockets = true;
        # Directory sockets stay open for the whole table. nginx's default 60s
        # proxy_read_timeout would tear them down; the server pings every 25s.
        extraConfig = ''
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
      };
    };
  };
}
