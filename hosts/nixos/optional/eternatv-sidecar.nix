{
  config,
  pkgs,
  eternatv,
  ...
}:

let
  sidecarPort = 8090;
  sidecarPkg = eternatv.packages.${pkgs.system}.eternatv-sidecar;
  # Must match `captureRetention` in radio-video.nix: the bucket prune
  # deletes capture MP4s after this many days, so the DB rows pointing at
  # them have to go on the same schedule or "Your Captures" fills with
  # entries that 404 on playback.
  captureRetentionDays = 7;
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
  # enable is also set by pirousync.nix; set it here too (idempotent merge)
  # so this module keeps working if that one is ever dropped.
  services.postgresql = {
    enable = true;
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

  # ── DB-side retention ─────────────────────────────────────────────────────
  # Companion to radio-video-captures-prune (radio-video.nix), which deletes
  # the MP4s from the garage bucket after ${toString captureRetentionDays}d.
  # Nothing else sweeps the capture rows, so without this every capture
  # eventually becomes a dead "Your Captures" entry pointing at a pruned file.
  systemd.services.eternatv-captures-db-prune = {
    description = "Prune eternatv capture rows older than ${toString captureRetentionDays} days";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "eternatv";
      Group = "eternatv";
      ExecStart = pkgs.writeShellScript "eternatv-captures-db-prune" ''
        ${config.services.postgresql.package}/bin/psql -d eternatv -v ON_ERROR_STOP=1 \
          -c "DELETE FROM \"capture\" WHERE captured_at < now() - interval '${toString captureRetentionDays} days'"
      '';
    };
  };

  systemd.timers.eternatv-captures-db-prune = {
    description = "Daily prune of eternatv capture rows";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
