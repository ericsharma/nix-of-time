{ lib, ... }:

{
  # ── PiroueSync dev database ─────────────────────────────────────────────────
  # Provisions the local Postgres database used during `pnpm dev` against the
  # PiroueSync Hono server. Peer-auth via the Unix socket — no password, no
  # plaintext credential file.
  #
  # The production DB is declared separately in pirousync.nix when the deploy
  # gets refactored off the Podman+vite-preview shape.
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

  # Make `eric` own pirousync_dev so drizzle migrations (CREATE TABLE etc.)
  # have the rights they need. ALTER OWNER on a DB already owned by `eric`
  # is a no-op, so this is safe across rebuilds.
  systemd.services.postgresql.postStart = lib.mkAfter ''
    $PSQL -tAc 'ALTER DATABASE "pirousync_dev" OWNER TO "eric";'
  '';
}
