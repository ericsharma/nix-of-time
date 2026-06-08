{
  config,
  lib,
  pkgs,
  ...
}:

let
  # ── Tunables ───────────────────────────────────────────────────────────────
  bucket = "guitar";
  mountDir = "/srv/jellyfin/media"; # kept OUTSIDE jellyfin's StateDirectory
  cacheDir = "/var/cache/rclone-jellyfin";
  garageS3Endpoint = "http://127.0.0.1:3900";
  garageRegion = "garage"; # matches services.garage.settings.s3_api.s3_region
in
{
  # ── Jellyfin media server ─────────────────────────────────────────────────
  # Native nixpkgs module. Runs as the `jellyfin` user, listens on :8096.
  # Media is a read-only rclone FUSE mount of the garage `guitar` bucket
  # (see rclone-jellyfin below). After the first deploy, add a library in the
  # web setup wizard pointing at ${mountDir}.
  #
  # MKV note: the guitar clips are MPEG-2 video + AC3 audio in MKV — Jellyfin
  # direct-plays these on most clients, light-transcodes for the rest.
  services.jellyfin = {
    enable = true;
    openFirewall = false; # we open only 8096 below; skip Jellyfin's DLNA ports
  };

  # LAN access — reach it directly at http://trigkey:8096. Public exposure
  # still flows through Newt/Pangolin (add a route in the Pangolin dashboard:
  # jellyfin.ericsharma.xyz → 127.0.0.1:8096).
  networking.firewall.allowedTCPPorts = [ 8096 ];

  # ── Secret: garage read-only creds for the rclone mount ───────────────────
  #   jellyfin/rclone-env:
  #     AWS_ACCESS_KEY_ID=...
  #     AWS_SECRET_ACCESS_KEY=...
  sops.secrets."jellyfin/rclone-env" = {
    owner = "jellyfin";
  };

  # ── FUSE: needed for `rclone mount --allow-other` ─────────────────────────
  # (already enabled globally by radio.nix; asserting again is harmless)
  programs.fuse.userAllowOther = true;

  # ── Mount dir, owned by jellyfin ──────────────────────────────────────────
  systemd.tmpfiles.rules = [
    "d /srv/jellyfin 0755 jellyfin jellyfin -"
    "d ${mountDir}   0755 jellyfin jellyfin -"
  ];

  # ── rclone mount: garage bucket → ${mountDir} (read-only) ─────────────────
  # Inline rclone S3 remote called "guitar" via env vars — no config file on
  # disk, secrets stay in the sops-managed env file. Runs as the `jellyfin`
  # user so Jellyfin reads its own mount (no cross-user FUSE needed).
  systemd.services.rclone-jellyfin = {
    description = "rclone FUSE mount of garage bucket '${bucket}' for jellyfin";
    after = [
      "network-online.target"
      "garage.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "garage.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      RCLONE_CONFIG_GUITAR_TYPE = "s3";
      RCLONE_CONFIG_GUITAR_PROVIDER = "Other";
      RCLONE_CONFIG_GUITAR_ENDPOINT = garageS3Endpoint;
      RCLONE_CONFIG_GUITAR_REGION = garageRegion;
      RCLONE_CONFIG_GUITAR_FORCE_PATH_STYLE = "true";
      # Without ENV_AUTH the named remote ignores AWS_ACCESS_KEY_ID from the
      # env file and tries anonymous access (which garage rejects).
      RCLONE_CONFIG_GUITAR_ENV_AUTH = "true";
    };

    # rclone shells out to fusermount3; --allow-other needs the setuid wrapper
    # in /run/wrappers/bin (the in-store fusermount EPERMs for non-root).
    path = [ "/run/wrappers" ];

    serviceConfig = {
      Type = "notify";
      User = "jellyfin";
      Group = "jellyfin";
      EnvironmentFile = config.sops.secrets."jellyfin/rclone-env".path;
      CacheDirectory = "rclone-jellyfin"; # creates ${cacheDir}, owned by jellyfin
      ExecStart = lib.concatStringsSep " " [
        "${pkgs.rclone}/bin/rclone mount"
        "guitar:${bucket}"
        mountDir
        "--read-only"
        "--allow-other"
        "--vfs-cache-mode full"
        "--cache-dir ${cacheDir}"
        "--vfs-cache-max-size 5G"
        "--vfs-cache-max-age 168h"
        "--dir-cache-time 1m"
        "--poll-interval 30s"
      ];
      ExecStop = "/run/wrappers/bin/fusermount3 -u ${mountDir}";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Jellyfin must not start scanning until the media mount is up. (If you ever
  # restart rclone-jellyfin by hand, also restart jellyfin so it re-enters the
  # refreshed mount namespace.)
  systemd.services.jellyfin = {
    after = [ "rclone-jellyfin.service" ];
    requires = [ "rclone-jellyfin.service" ];
  };
}
