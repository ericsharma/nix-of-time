{ config, ... }:

{
  sops.secrets."restic/immich/password" = {};
  sops.secrets."restic/immich/env" = {};

  services.restic.backups.immich-media = {
    # ── Repository ───────────────────────────────────────────────────────────
    # Garage S3 API: http://192.168.0.4:3900  bucket: immich
    #
    # restic/immich/env must contain:
    #   AWS_ACCESS_KEY_ID=<garage-key-id>
    #   AWS_SECRET_ACCESS_KEY=<garage-secret>
    #   AWS_DEFAULT_REGION=garage
    #   RESTIC_REPOSITORY=s3:http://192.168.0.4:3900/immich
    #
    # Keeping the repository URL in the env file means you can change the
    # Garage host/port/bucket without touching this module.
    repositoryFile = null;          # overridden by RESTIC_REPOSITORY in env
    environmentFile = config.sops.secrets."restic/immich/env".path;
    passwordFile    = config.sops.secrets."restic/immich/password".path;

    # ── What to back up ──────────────────────────────────────────────────────
    paths = [ "/mnt/immich-data/immich" ];

    # ── Schedule ─────────────────────────────────────────────────────────────
    timerConfig = {
      OnCalendar = "02:00";   # Run nightly at 2 AM
      Persistent  = true;     # Run immediately on next boot if missed
    };

    # ── Retention ────────────────────────────────────────────────────────────
    pruneOpts = [
      "--keep-daily   7"
      "--keep-weekly  4"
      "--keep-monthly 6"
    ];

    # ── Init ─────────────────────────────────────────────────────────────────
    # Automatically initialise the repo on first run if it doesn't exist yet.
    initialize = true;
  };
}
