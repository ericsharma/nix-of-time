{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Single repository on gmktec's T7, served by restic-rest-server.
  # `restic forget` groups snapshots by host+paths, so one repo holds every job
  # and each job's snapshots are pruned against their own group.
  repositoryFile = config.sops.secrets."restic/repository".path;
  passwordFile = config.sops.secrets."restic/password".path;

  dumpDir = "/var/backup/dumps";

  # Postgres containers inside the docker-services LXC. POSTGRES_USER is read
  # from each container's own environment, so credentials stay out of the store.
  lxcPostgres = [
    "endurain-postgres"
    "koito-db"
    "rybbit-postgres"
    "dawarich-db"
  ];

  incus = "${config.virtualisation.incus.package}/bin/incus";
  zstd = "${pkgs.zstd}/bin/zstd";

  common = {
    inherit repositoryFile passwordFile;
    initialize = true;
    # --one-file-system keeps the rclone FUSE mounts (Jellyfin media, radio
    # music, radio-video captures) out of the snapshot. Those are views of
    # Garage buckets and are already covered by the `garage` job.
    extraBackupArgs = [
      "--one-file-system"
      "--exclude-caches"
    ];
  };

  retention = [
    "--group-by host,paths"
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
in
{
  # ── Secrets ──────────────────────────────────────────────────────────────────
  # restic/repository — rest:http://trigkey:<pass>@192.168.0.51:8000/trigkey
  #   The HTTP password is part of the URL, so the whole URL is a secret.
  # restic/password   — the repository encryption password. Losing this makes
  #   every backup permanently unreadable. It is also in your password manager.
  sops.secrets."restic/repository" = { };
  sops.secrets."restic/password" = { };

  systemd.tmpfiles.rules = [
    "d /var/backup   0700 root root -"
    "d ${dumpDir}    0700 root root -"
  ];

  # restic needs to reach gmktec; make failures visible in the journal.
  environment.systemPackages = [ pkgs.restic ];

  services.restic.backups = {

    # ── 1. Databases (01:30) ───────────────────────────────────────────────────
    # Logical dumps, not file copies. A copied live Postgres data directory is
    # not guaranteed to restore; a dump is.
    databases = common // {
      paths = [ dumpDir ];
      timerConfig = {
        OnCalendar = "01:30";
        Persistent = true;
      };
      backupPrepareCommand = ''
        set -euo pipefail
        umask 077
        rm -f ${dumpDir}/*.sql.zst

        # trigkey's own Postgres: immich, eternatv, pirousync, eric_portfolio,
        # options-ledger. --clean makes the dump self-contained on restore.
        ${pkgs.util-linux}/bin/runuser -u postgres -- \
          ${config.services.postgresql.package}/bin/pg_dumpall --clean \
          | ${zstd} -q -T0 -6 -o ${dumpDir}/trigkey-postgresql.sql.zst -f

        # Postgres instances inside the docker-services LXC. incus exec avoids
        # needing an SSH key for root.
        ${lib.concatMapStringsSep "\n" (c: ''
          ${incus} exec docker-services -- \
            docker exec ${c} sh -c 'pg_dumpall -U "$POSTGRES_USER"' \
            | ${zstd} -q -T0 -6 -o ${dumpDir}/lxc-${c}.sql.zst -f
        '') lxcPostgres}
      '';
    };

    # ── 2. Immich media (02:00) ────────────────────────────────────────────────
    # 104 GB on the external 1.8 TB disk. The immich database is covered by the
    # `databases` job above — both are needed for a working restore.
    immich = common // {
      paths = [ "/mnt/immich-data/immich" ];
      timerConfig = {
        OnCalendar = "02:00";
        Persistent = true;
      };
    };

    # ── 3. Garage object storage (03:00) ───────────────────────────────────────
    # data/ holds immutable content-addressed blocks and is safe to copy live.
    # The live LMDB metadata is not, so it is excluded and replaced by a
    # consistent snapshot taken in the prepare step.
    garage = common // {
      paths = [
        "/var/lib/garage/data"
        "/var/lib/garage/meta"
      ];
      exclude = [ "/var/lib/garage/meta/db.lmdb" ];
      timerConfig = {
        OnCalendar = "03:00";
        Persistent = true;
      };
      backupPrepareCommand = ''
        set -euo pipefail
        # Drop previous snapshots so the backup carries exactly one, then take
        # a fresh consistent copy of the metadata database.
        ${pkgs.findutils}/bin/find /var/lib/garage/meta/snapshots \
          -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
        ${config.services.garage.package}/bin/garage meta snapshot

        # Fail loudly rather than ship a data-only backup. Without the metadata
        # snapshot the blocks in data/ cannot be restored to a working node,
        # and a silent `garage meta snapshot` failure would be invisible until
        # the day it mattered.
        snap=$(${pkgs.findutils}/bin/find /var/lib/garage/meta/snapshots \
                 -mindepth 2 -maxdepth 2 -name db.lmdb -type f -size +0 2>/dev/null | head -1)
        if [ -z "$snap" ]; then
          echo "garage meta snapshot produced no metadata file; refusing to" >&2
          echo "take a data-only backup that could not be restored" >&2
          exit 1
        fi
      '';
    };

    # ── 4. docker-services data (04:00) ────────────────────────────────────────
    # Host-backed volumes for the LXC stacks: rybbit, dawarich, karakeep,
    # koito, endurain. Their Postgres dumps ride in the `databases` job.
    # ClickHouse (rybbit analytics) is file-level only — see docs/services/backup.md.
    docker-services = common // {
      paths = [ "/srv/docker-services" ];
      timerConfig = {
        OnCalendar = "04:00";
        Persistent = true;
      };
    };

    # ── 5. System and service state (04:30) ────────────────────────────────────
    # Runs last and carries the retention pass for the whole repository, so
    # `forget --prune` walks the 150 GB repo once per night rather than five
    # times. runCheck verifies a rolling 2% of the data each night.
    system-state = common // {
      paths = [
        "/var/lib/hass"
        "/var/lib/grafana"
        "/var/lib/hermes"
        "/var/lib/prometheus2"
        "/var/lib/private/newt"
        "/var/lib/private/tapmap"
        "/srv/kavita"
        "/srv/memos"
        "/srv/obsidian"
        "/srv/tapmap"
        "/srv/strava"
        "/srv/termix"
        "/srv/komodo"
        "/srv/multi-scrobbler"
        "/srv/transcription"
      ];
      timerConfig = {
        OnCalendar = "04:30";
        Persistent = true;
      };
      pruneOpts = retention;
      runCheck = true;
      checkOpts = [ "--read-data-subset=2%" ];
    };
  };

  # ── Deliberately not backed up ───────────────────────────────────────────────
  #   /var/lib/private/ollama  13 GB of re-downloadable model weights
  #   /var/lib/containers      Podman image cache, rebuilt from pinned tags
  #   /var/lib/incus           LXC rootfs; declarative, data is bind-mounted
  #   /srv/jellyfin            rclone view of the Garage `guitar` bucket
}
