{ pkgs, options-ledger, ... }:

let
  # ── Static Vite SPA (pnpm) ───────────────────────────────────────────────────
  # Built at Nix eval time via pnpm offline cache. No runtime server, no secrets
  # — nginx serves the dist/ directory directly from the Nix store.
  #
  # First build will fail with a hash mismatch on pnpmDeps.hash. Copy the "got:"
  # hash printed by Nix into the value below and rebuild.
  pnpmDeps = pkgs.pnpm.fetchDeps {
    pname = "options-ledger";
    version = "0.0.0";
    src = options-ledger;
    fetcherVersion = 2;
    hash = "sha256-uWHyWJmB5EF1aeTnbQwmE3uGnHpPNvvu+IAjrRSC70s=";
  };

  site = pkgs.stdenv.mkDerivation {
    pname = "options-ledger";
    version = "0.0.0";
    src = options-ledger;
    inherit pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.pnpm
      pkgs.pnpm.configHook
    ];

    buildPhase = ''
      runHook preBuild
      pnpm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  # ── Yahoo Finance proxy (Hono + yahoo-finance2 + pg, npm) ───────────────────
  # Tiny Node service that the SPA calls via same-origin /api/*. Reads from
  # Yahoo, caches in memory, queries Postgres for portfolio data, serves JSON.
  # No build step — `node index.js`.
  #
  # npm (not pnpm) is used here so that node_modules is flat: yahoo-finance2's
  # `@deno/shim-deno` and pg's CJS transitive deps are all present at runtime
  # by construction. See ~/options-ledger/NOTES.md.
  #
  # First build will fail with `npmDepsHash` mismatch. Copy the "got:" hash
  # printed by Nix into the value below and rebuild.
  proxy = pkgs.buildNpmPackage {
    pname = "options-ledger-server";
    version = "0.0.0";
    src = "${options-ledger}/server";
    npmDepsHash = "sha256-dsmLbYdzoZafk3VkGFa90rKY+NZOIZKG2qk882TphRQ=";
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r index.js portfolio-db.js node_modules package.json $out/
      runHook postInstall
    '';
  };
in
{
  # ── OPT.LEDGER (personal options-tracking ledger) ───────────────────────────
  # SPA port:   4205 (localhost, fronted by Pangolin/Newt → options.ericsharma.xyz)
  # Proxy port: 4206 (localhost; reached only via nginx /api/ on the same vhost,
  #                   so it inherits the Pangolin auth that gates the SPA).

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."options.ericsharma.xyz" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 4205;
        }
      ];
      root = "${site}";
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:4206/api/";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_read_timeout 30s;
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        '';
      };
    };
  };

  # Stable system user so Postgres can peer-auth this service on /run/postgresql
  # (DynamicUser allocates a random UID that has no matching PG role).
  users.users.options-ledger-server = {
    isSystemUser = true;
    group = "options-ledger-server";
    description = "options-ledger Yahoo Finance proxy";
  };
  users.groups.options-ledger-server = { };

  systemd.services.options-ledger-server = {
    description = "options-ledger Yahoo Finance proxy";
    after = [ "network-online.target" "postgresql.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOST = "127.0.0.1";
      PORT = "4206";
      NODE_ENV = "production";
      # Portfolio data lives in the state directory (gitignored, never in Nix store).
      # Copy server/data/portfolio.local.json to this path once after first deploy.
      PORTFOLIO_DATA_PATH = "/var/lib/options-ledger-server/portfolio.local.json";
      # Local eric_portfolio DB (per-account balances, holdings, prices).
      # Loader at ~/eric-portfolio-db re-imports it from Eric Copy.xlsx.
      PORTFOLIO_DATABASE_URL = "postgres://options-ledger-server@/eric_portfolio?host=/run/postgresql";
    };
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node ${proxy}/index.js";
      Restart = "on-failure";
      RestartSec = "5s";

      User = "options-ledger-server";
      Group = "options-ledger-server";
      StateDirectory = "options-ledger-server";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      # AF_UNIX needed for the Postgres /run/postgresql socket.
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };
}
