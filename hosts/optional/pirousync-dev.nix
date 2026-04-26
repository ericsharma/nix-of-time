{ config, ... }:

{
  # ── PiroueSync dev database ─────────────────────────────────────────────────
  # Provisions the local Postgres database used during `pnpm dev` against the
  # PiroueSync Hono server. Peer-auth via the Unix socket — no password, no
  # plaintext credential file.
  #
  # The production DB is declared separately in pirousync.nix.
  #
  # In PiroueSync/.env.local set:
  #   DATABASE_URL=postgres:///pirousync_dev?host=/run/postgresql

  services.postgresql = {
    enable          = true;  # already true via services.immich; merges idempotently
    ensureDatabases = [ "pirousync_dev" ];
    ensureUsers = [
      {
        name                = "eric";
        ensureClauses.login = true;
      }
    ];
  };

  # `ensureDBOwnership = true` only works when role name == DB name. Since we
  # want `eric` to own `pirousync_dev`, do the ALTER DATABASE in a separate
  # oneshot ordered AFTER postgresql-setup.service (where ensureUsers runs).
  # Idempotent across rebuilds.
  systemd.services.pirousync-dev-postgres-setup = {
    description = "Set pirousync_dev DB ownership to eric";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "postgresql-setup.service" ];
    requires    = [ "postgresql-setup.service" ];
    serviceConfig = {
      Type            = "oneshot";
      User            = "postgres";
      RemainAfterExit = true;
      ExecStart       = ''${config.services.postgresql.package}/bin/psql -tAc 'ALTER DATABASE "pirousync_dev" OWNER TO "eric";' '';
    };
  };
}
