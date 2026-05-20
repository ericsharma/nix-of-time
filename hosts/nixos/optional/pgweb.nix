{ pkgs, ... }:

{
  # ── pgweb — PostgreSQL browser ────────────────────────────────────────────────
  # Binds to 127.0.0.1:5435. Sessions mode: the login page shows pre-configured
  # bookmarks for each local database, each connecting via Unix socket (peer auth,
  # no password). Expose externally via Newt if needed.

  # pgweb superuser so peer auth grants access to every database.
  services.postgresql.ensureUsers = [
    {
      name = "pgweb";
      ensureClauses = {
        login = true;
        superuser = true;
      };
    }
  ];

  users.users.pgweb = {
    isSystemUser = true;
    group = "pgweb";
  };
  users.groups.pgweb = { };

  # One bookmark file per database — all via Unix socket, no password.
  environment.etc = {
    "pgweb/bookmarks/immich.toml".text = ''
      url = "postgres:///immich?host=/run/postgresql&sslmode=disable"
    '';
    "pgweb/bookmarks/pirousync.toml".text = ''
      url = "postgres:///pirousync?host=/run/postgresql&sslmode=disable"
    '';
    "pgweb/bookmarks/pirousync_dev.toml".text = ''
      url = "postgres:///pirousync_dev?host=/run/postgresql&sslmode=disable"
    '';
  };

  systemd.services.pgweb = {
    description = "pgweb PostgreSQL browser";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.pgweb}/bin/pgweb --bind 127.0.0.1 --listen 5435 --sessions --bookmarks-dir /etc/pgweb/bookmarks --skip-open";
      User = "pgweb";
      Group = "pgweb";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
