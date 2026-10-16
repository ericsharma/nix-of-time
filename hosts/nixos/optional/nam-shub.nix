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
}
