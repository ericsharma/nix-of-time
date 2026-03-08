{ config, ... }:

{
  # ── Strava Statistics ────────────────────────────────────────────────────────
  # Data dirs: /srv/strava/{build,database,files,config}
  # Port: 7080

  sops.secrets."strava/env" = {};

  virtualisation.oci-containers.containers.strava-statistics = {
    image = "robiningelbrecht/strava-statistics:latest";
    ports = [ "127.0.0.1:7080:8080" ];
    volumes = [
      "/srv/strava/build:/var/www/build"
      "/srv/strava/database:/var/www/storage/database"
      "/srv/strava/files:/var/www/storage/files"
      "/srv/strava/config:/var/www/config/app"
    ];
    environmentFiles = [
      config.sops.secrets."strava/env".path
    ];
    environment = {
      MANIFEST_APP_URL           = "http://localhost:7080/";
      NUMBER_OF_NEW_ACTIVITIES_TO_PROCESS_PER_IMPORT = "250";
      IMPORT_AND_BUILD_SCHEDULE  = "5 4 * * *";
      TZ                         = "Etc/GMT";
      LOCALE                     = "en_US";
      UNIT_SYSTEM                = "imperial";
      TIME_FORMAT                = "12";
      DATE_FORMAT                = "MONTH-DAY-YEAR";
      SPORT_TYPES_TO_IMPORT      = "[]";
      ATHLETE_BIRTHDAY           = "1995-07-10";
      ATHLETE_WEIGHTS            = ''{"2016-01-01": 97, "2018-01-01": 93, "2019-01-01": 90, "2020-01-01": 87}'';
      FTP_VALUES                 = "[]";
      NTFY_URL                   = "";
      ACTIVITIES_TO_SKIP_DURING_IMPORT = "[]";
    };
  };

  # ── Manual import/build (run with: sudo systemctl start strava-import) ─────
  systemd.services.strava-import = {
    description = "Strava Statistics: import data and build files";
    after = [ "podman-strava-statistics.service" ];
    requires = [ "podman-strava-statistics.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = let
        script = "/run/current-system/sw/bin/podman exec strava-statistics bin/console app:strava:import-data && /run/current-system/sw/bin/podman exec strava-statistics bin/console app:strava:build-files";
      in "/run/current-system/sw/bin/bash -c '${script}'";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/strava 0755 root root -"
    "d /srv/strava/build 0755 root root -"
    "d /srv/strava/database 0755 root root -"
    "d /srv/strava/files 0755 root root -"
    "d /srv/strava/config 0755 root root -"
  ];
}
