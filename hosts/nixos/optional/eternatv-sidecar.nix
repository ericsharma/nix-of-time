{
  config,
  pkgs,
  eternatv,
  ...
}:

let
  sidecarPort = 8090;
  sidecarPkg = eternatv.packages.${pkgs.system}.eternatv-sidecar;
in
{
  # ── System user ──────────────────────────────────────────────────────────────
  users.users.eternatv = {
    isSystemUser = true;
    group = "eternatv";
    description = "EternaTV Hono sidecar";
  };
  users.groups.eternatv = { };

  # ── Postgres: database owned by the service user ──────────────────────────────
  # services.postgresql.enable is set by pirousync.nix which is also loaded.
  services.postgresql = {
    ensureDatabases = [ "eternatv" ];
    ensureUsers = [
      {
        name = "eternatv";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
  };

  # ── Secret: AUTH_SECRET (env-file format, loaded by the systemd unit) ─────────
  # Add to secrets/secrets.yaml under `eternatv-sidecar/env`:
  #   AUTH_SECRET=<openssl rand -hex 32>
  sops.secrets."eternatv-sidecar/env" = {
    owner = "eternatv";
  };

  # ── Hono sidecar service ──────────────────────────────────────────────────────
  systemd.services.eternatv-sidecar = {
    description = "EternaTV Hono auth sidecar (port ${toString sidecarPort})";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "postgresql.service"
    ];
    requires = [ "postgresql.service" ];

    environment = {
      PORT = toString sidecarPort;
      NODE_ENV = "production";
      DATABASE_URL = "postgres://eternatv@/eternatv?host=/run/postgresql";
      ORCHESTRATOR_URL = "http://127.0.0.1:8089";
      BASE_URL = "https://video.ericsharma.xyz";
    };

    serviceConfig = {
      User = "eternatv";
      Group = "eternatv";
      ExecStart = "${sidecarPkg}/bin/eternatv-sidecar";
      Restart = "on-failure";
      RestartSec = "5s";
      EnvironmentFile = config.sops.secrets."eternatv-sidecar/env".path;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };
}
