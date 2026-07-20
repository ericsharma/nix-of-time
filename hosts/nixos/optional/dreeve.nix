{ config, pkgs, ... }:

# ── Dreeve (formerly Statistics for Strava) ──────────────────────────────────
# Athletic activity analytics. Runs in `files` import mode: activity files are
# dropped into /srv/strava/watch and picked up by the daemon, which imports and
# rebuilds the static frontend every few minutes.
#
# Endurain (docker-services LXC) is the source of truth for new activities — it
# pulls them from Garmin Connect and keeps the original .fit files, which the
# dreeve-sync timer below copies into the watch folder. Strava is no longer
# used: its API went subscription-only on 2026-06-01.
#
# Port: 7080 (localhost only)
# Data: /srv/strava/{build,database,files,watch}
# The database file is still strava.db — v5 reads the v4 name as-is.

let
  image = "docker.io/robiningelbrecht/dreeve:v5.0.0";

  # Shared by the app and daemon containers — upstream requires both to mount
  # exactly the same volumes.
  sharedVolumes = [
    # MIGRATION ONLY: v5 reads config.yaml on first boot and writes every
    # setting into the database. Remove this line (and delete /srv/strava/config)
    # once the settings are confirmed in the admin panel — from then on
    # config.yaml is ignored and everything is edited in the browser.
    "/srv/strava/config:/var/www/config/app"
    "/srv/strava/build:/var/www/build"
    "/srv/strava/database:/var/www/storage/database"
    "/srv/strava/files:/var/www/storage/files"
    "/srv/strava/watch:/var/www/watch"
    # Patch: upstream LiveOpenMeteo still only catches JsonException|ConnectException
    # in v5, so open-meteo 5xx responses abort the whole import. Broaden to
    # GuzzleException. Drop this mount if a future image fixes it upstream.
    "/srv/strava/patches/LiveOpenMeteo.php:/var/www/src/Domain/Integration/Weather/OpenMeteo/LiveOpenMeteo.php:ro"
  ];

  sharedEnvironment = {
    IMPORT_MODE = "files";
    APP_URL = "http://localhost:7080";
    TZ = "America/New_York";
  };

  dreeve-update = pkgs.writeShellScript "dreeve-update" ''
    set -euo pipefail
    OLD=$(podman image inspect ${image} --format '{{.Id}}' 2>/dev/null || true)
    podman pull ${image}
    NEW=$(podman image inspect ${image} --format '{{.Id}}')
    if [ "$OLD" != "$NEW" ]; then
      systemctl restart podman-dreeve.service podman-dreeve-daemon.service
    fi
  '';

  # Copy new .fit files from Endurain into dreeve's watch folder. Both live on
  # this host, so this is a local copy. -n never clobbers, and dreeve silently
  # skips activities it has already imported, so re-runs are harmless.
  dreeve-sync = pkgs.writeShellScript "dreeve-sync" ''
    set -euo pipefail
    SRC=/srv/docker-services/endurain/data/activity_files/processed
    DST=/srv/strava/watch
    if [ ! -d "$SRC" ]; then
      echo "endurain activity_files not present at $SRC — nothing to sync"
      exit 0
    fi
    # Prefix with endurain- so the names can't collide with anything else
    # dropped into the watch folder by hand.
    count=0
    for f in "$SRC"/*.fit; do
      [ -e "$f" ] || continue
      target="$DST/endurain-$(basename "$f")"
      if [ ! -e "$target" ]; then
        cp -n "$f" "$target"
        count=$((count + 1))
      fi
    done
    echo "synced $count new activity file(s) into $DST"
  '';
in
{
  sops.secrets."strava/env" = { };

  # ── App ────────────────────────────────────────────────────────────────────
  virtualisation.oci-containers.containers.dreeve = {
    inherit image;
    ports = [ "127.0.0.1:7080:8080" ];
    volumes = sharedVolumes;
    environmentFiles = [ config.sops.secrets."strava/env".path ];
    environment = sharedEnvironment;
  };

  # ── Daemon (required in v5; runs the recurring import/build) ───────────────
  virtualisation.oci-containers.containers.dreeve-daemon = {
    inherit image;
    volumes = sharedVolumes;
    environmentFiles = [ config.sops.secrets."strava/env".path ];
    environment = sharedEnvironment;
    cmd = [
      "bin/console"
      "app:daemon:run"
    ];
  };

  # ── Daily image update ─────────────────────────────────────────────────────
  systemd.services.dreeve-update = {
    description = "Pull latest dreeve image and restart if updated";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ config.virtualisation.podman.package ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = dreeve-update;
    };
  };

  systemd.timers.dreeve-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # ── Endurain → watch folder sync ───────────────────────────────────────────
  systemd.services.dreeve-sync = {
    description = "Copy new Endurain activity files into dreeve's watch folder";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = dreeve-sync;
    };
  };

  systemd.timers.dreeve-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/15";
      Persistent = true;
      RandomizedDelaySec = "2m";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/strava 0755 root root -"
    "d /srv/strava/build 0755 root root -"
    "d /srv/strava/database 0755 root root -"
    "d /srv/strava/files 0755 root root -"
    "d /srv/strava/watch 0755 root root -"
    "d /srv/strava/patches 0755 root root -"
  ];
}
