{ pkgs, ... }:

let
  checkout = "/home/eric/nam-shub";
  port = 4220;
in
{
  # ── nam-shub (personal wisdom index) ─────────────────────────────────────────
  # Kindle highlights, later Karakeep and web captures, in one searchable index.
  # Source: ~/nam-shub (pnpm workspace, no GitHub remote yet).
  # Port:   4220 (127.0.0.1). LAN name `nam-shub.local` through portless —
  #         see inventory.nix. No auth, so it stays off Pangolin.
  # Sync:   nam-shub-sync.timer runs the import plugins hourly (Karakeep
  #         highlights, Memos #quotes).
  # Data:   ~/nam-shub/data/nam-shub.db (SQLite). Backed up by the
  #         system-state restic job in trigkey/backup.nix.
  #
  # This runs from the checkout as eric, not from a Nix build, because the
  # project changes daily and the import commands (`corepack pnpm pull:kindle`,
  # `import:kindle`) write the same database file. After a change:
  #   web UI:  corepack pnpm build           (served from apps/web/dist)
  #   server:  sudo systemctl restart nam-shub
  systemd.services.nam-shub = {
    description = "nam-shub wisdom index (port ${toString port})";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      HOST = "127.0.0.1";
      PORT = toString port;
      NS_DB_FILE = "${checkout}/data/nam-shub.db";
      NODE_ENV = "production";
      # node:sqlite prints an ExperimentalWarning on every start.
      NODE_NO_WARNINGS = "1";
    };

    serviceConfig = {
      User = "eric";
      Group = "users";
      WorkingDirectory = checkout;
      ExecStart = "${pkgs.nodejs_22}/bin/node apps/server/src/index.ts";
      Restart = "on-failure";
      RestartSec = "5s";

      # Hardening. The home directory is read-only except the data folder,
      # which needs write access for the database and its WAL files.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "${checkout}/data" ];
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
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

  # ── Hourly plugin sync ───────────────────────────────────────────────────────
  # Runs every import plugin (`corepack pnpm sync --list` in the checkout).
  # The plugins open the Karakeep and Memos SQLite files read-only (both are
  # world-readable on the host), so no API key or token is needed. Safe to
  # run again: each item is keyed by its ID in the outside service.
  systemd.services.nam-shub-sync = {
    description = "nam-shub: run the import plugins";
    after = [ "nam-shub.service" ];
    environment = {
      NS_DB_FILE = "${checkout}/data/nam-shub.db";
      KARAKEEP_DB_FILE = "/srv/docker-services/karakeep/data/db.db";
      MEMOS_DB_FILE = "/srv/memos/memos_prod.db";
      NODE_NO_WARNINGS = "1";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "eric";
      Group = "users";
      WorkingDirectory = checkout;
      ExecStart = "${pkgs.nodejs_22}/bin/node apps/server/src/cli/sync.ts";

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ "${checkout}/data" ];
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = true;
    };
  };

  systemd.timers.nam-shub-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      RandomizedDelaySec = "5m";
      Persistent = true;
    };
  };
}
