{ config, pkgs, ... }:

# The Pangolin cluster's shared state (docs/plans/pangolin-cluster.md):
# a `pangolin` database on trigkey's existing PostgreSQL, and a Valkey-
# compatible Redis for cross-node pub/sub. Reached by the nodes over
# wg-pangolin only (optional/wg-pangolin.nix).
#
# Backups: backup.nix already runs pg_dumpall nightly, so the database is in
# the restic set with no extra work.
#
# Passwords live in secrets/pangolin.yaml (trigkey is a recipient), so the
# server here and the clients on the nodes read the same value.
let
  pg = config.services.postgresql.package;
in
{
  sops.secrets."pangolin-db/password" = {
    sopsFile = ../../../secrets/pangolin.yaml;
    owner = "postgres";
  };
  sops.secrets."pangolin-redis/password" = {
    sopsFile = ../../../secrets/pangolin.yaml;
    owner = config.services.redis.servers.pangolin.user;
  };

  # ── PostgreSQL ───────────────────────────────────────────────────────────────
  # One server for Immich, pirousync and Pangolin. It listens on every address
  # instead of 10.100.0.1: binding that address would fail whenever the
  # WireGuard interface comes up after PostgreSQL, and take Immich down with
  # it. The firewall opens 5432 on wg-pangolin only, and pg_hba admits the
  # pangolin role from the nodes only.
  services.postgresql = {
    enableTCPIP = true;
    ensureDatabases = [ "pangolin" ];
    ensureUsers = [
      {
        name = "pangolin";
        ensureDBOwnership = true;
        ensureClauses.login = true;
      }
    ];
    authentication = ''
      host pangolin pangolin 10.100.0.11/32 scram-sha-256
      host pangolin pangolin 10.100.0.12/32 scram-sha-256
    '';
  };

  # ensureUsers makes the role without a password; set it from sops.
  systemd.services.pangolin-db-password = {
    description = "Set the pangolin PostgreSQL role's password from sops";
    wantedBy = [ "multi-user.target" ];
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStart = pkgs.writeShellScript "pangolin-db-password" ''
        echo "ALTER ROLE pangolin PASSWORD :'pw';" | ${pg}/bin/psql -v ON_ERROR_STOP=1 \
          -v pw="$(cat ${config.sops.secrets."pangolin-db/password".path})"
      '';
    };
  };

  # ── Valkey / Redis ───────────────────────────────────────────────────────────
  # Only Pangolin uses this instance, so it binds the WireGuard address and
  # waits for the interface.
  services.redis.servers.pangolin = {
    enable = true;
    bind = "10.100.0.1";
    port = 6379;
    requirePassFile = config.sops.secrets."pangolin-redis/password".path;
  };
  systemd.services.redis-pangolin = {
    after = [ "wireguard-wg-pangolin.service" ];
    requires = [ "wireguard-wg-pangolin.service" ];
  };

  networking.firewall.interfaces.wg-pangolin.allowedTCPPorts = [
    5432
    6379
  ];
}
