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
    hash = "sha256-8hhuup6HpAcqipqnmEpyIAnRxSa1nLMO/ATHIdP/QII=";
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

  # ── Yahoo Finance proxy (Hono + yahoo-finance2, pnpm) ───────────────────────
  # Tiny Node service that the SPA calls via same-origin /api/*. Reads from
  # Yahoo, caches in memory, serves JSON. No build step — `node index.js`.
  #
  # server/ is a pnpm workspace member; reuses the workspace pnpmDeps above.
  # `pnpm deploy` produces a self-contained directory with resolved node_modules.
  proxy = pkgs.stdenv.mkDerivation {
    pname = "options-ledger-server";
    version = "0.0.0";
    src = options-ledger;
    inherit pnpmDeps;

    nativeBuildInputs = [
      pkgs.nodejs
      pkgs.pnpm
      pkgs.pnpm.configHook
      pkgs.esbuild
    ];

    buildPhase = ''
      runHook preBuild
      # Stub out @deno/shim-deno — yahoo-finance2 imports it via _dnt.shims.js
      # but only uses standard fetch at runtime; no actual Deno file/net APIs.
      cat > deno-shim-stub.mjs << 'STUBEOF'
const tty = (s) => ({ isTerminal: () => s.isTTY || false });
export const Deno = {
  env: {
    get: (k) => process.env[k],
    set: (k, v) => { process.env[k] = String(v); },
    delete: (k) => { delete process.env[k]; },
    has: (k) => k in process.env,
    toObject: () => Object.assign({}, process.env),
  },
  build: { os: "linux", arch: "x86_64", target: "x86_64-unknown-linux-gnu" },
  noColor: true,
  pid: process.pid,
  version: { deno: "2.0.0", v8: "12.0.0", typescript: "5.0.0" },
  exit: (code) => process.exit(code ?? 0),
  args: process.argv.slice(2),
  mainModule: "",
  stdin: tty(process.stdin),
  stdout: tty(process.stdout),
  stderr: tty(process.stderr),
};
STUBEOF
      cd server
      esbuild index.js \
        --bundle \
        --platform=node \
        --format=esm \
        --outfile=bundle.js \
        --external:'node:*' \
        "--alias:@deno/shim-deno=../deno-shim-stub.mjs"
      cd ..
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp server/bundle.js $out/index.js
      cp server/package.json $out/
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

  systemd.services.options-ledger-server = {
    description = "options-ledger Yahoo Finance proxy";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      HOST = "127.0.0.1";
      PORT = "4206";
      NODE_ENV = "production";
      # Portfolio data lives in the state directory (gitignored, never in Nix store).
      # Copy server/data/portfolio.local.json to this path once after first deploy.
      PORTFOLIO_DATA_PATH = "/var/lib/options-ledger-server/portfolio.local.json";
    };
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node ${proxy}/index.js";
      Restart = "on-failure";
      RestartSec = "5s";

      DynamicUser = true;
      StateDirectory = "options-ledger-server";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };
}
