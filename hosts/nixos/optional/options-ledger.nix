{ pkgs, options-ledger, ... }:

let
  # ── Static Vite SPA ──────────────────────────────────────────────────────────
  # Built at Nix eval time. No runtime server, no secrets — nginx serves the
  # dist/ directory directly from the Nix store.
  #
  # First build will fail with a hash mismatch on npmDepsHash. Copy the "got:"
  # hash printed by Nix into the value below and rebuild.
  site = pkgs.buildNpmPackage {
    pname = "options-ledger";
    version = "0.0.0";
    src = options-ledger;

    npmDepsHash = "sha256-5s1I/ZsXwegR6L+NXzXOLOYQpAYn9KxKbRtggUnTtTY=";

    # `npm run build` writes to dist/, which we copy out as the package output.
    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  # ── Yahoo Finance proxy (Hono + yahoo-finance2) ──────────────────────────────
  # Tiny Node service that the SPA calls via same-origin /api/*. Reads from
  # Yahoo, caches in memory, serves JSON. No build step — `node index.js`.
  #
  # First build will fail with a hash mismatch on npmDepsHash; copy the "got:"
  # hash Nix prints and rebuild.
  proxy = pkgs.buildNpmPackage {
    pname = "options-ledger-server";
    version = "0.0.0";
    src = "${options-ledger}/server";

    npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r index.js node_modules package.json $out/
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
    };
    serviceConfig = {
      ExecStart = "${pkgs.nodejs}/bin/node ${proxy}/index.js";
      Restart = "on-failure";
      RestartSec = "5s";

      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };
}
