{ config, ... }:

{
  # ── Dawarich (location tracking) ─────────────────────────────────────────────
  # Data dirs: /srv/dawarich/{db,shared,public,watched,storage}
  # Port: 3000

  sops.secrets."dawarich/env" = {};

  virtualisation.oci-containers.containers.dawarich-redis = {
    image = "redis:7.4-alpine";
    cmd = [ "redis-server" ];
    volumes = [
      "/srv/dawarich/shared:/data"
    ];
    extraOptions = [
      "--network=dawarich"
      "--health-cmd=redis-cli --raw incr ping"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-start-period=30s"
      "--health-timeout=10s"
    ];
  };

  virtualisation.oci-containers.containers.dawarich-db = {
    image = "postgis/postgis:17-3.5-alpine";
    volumes = [
      "/srv/dawarich/db:/var/lib/postgresql/data"
      "/srv/dawarich/shared:/var/shared"
    ];
    environment = {
      POSTGRES_DB = "dawarich_development";
    };
    environmentFiles = [
      config.sops.secrets."dawarich/env".path
    ];
    extraOptions = [
      "--network=dawarich"
      "--shm-size=1g"
      "--health-cmd=pg_isready -U postgres -d dawarich_development"
      "--health-interval=10s"
      "--health-retries=5"
      "--health-start-period=30s"
      "--health-timeout=10s"
    ];
  };

  virtualisation.oci-containers.containers.dawarich-app = {
    image = "freikin/dawarich:latest";
    dependsOn = [ "dawarich-db" "dawarich-redis" ];
    ports = [ "127.0.0.1:3000:3000" ];
    volumes = [
      "/srv/dawarich/public:/var/app/public"
      "/srv/dawarich/watched:/var/app/tmp/imports/watched"
      "/srv/dawarich/storage:/var/app/storage"
      "/srv/dawarich/db:/dawarich_db_data"
    ];
    entrypoint = "web-entrypoint.sh";
    cmd = [ "bin/rails" "server" "-p" "3000" "-b" "::" ];
    environment = {
      RAILS_ENV           = "development";
      REDIS_URL           = "redis://dawarich-redis:6379";
      DATABASE_HOST       = "dawarich-db";
      DATABASE_USERNAME   = "postgres";
      DATABASE_PASSWORD   = "password";
      DATABASE_NAME       = "dawarich_development";
      MIN_MINUTES_SPENT_IN_CITY = "60";
      APPLICATION_HOSTS   = "localhost";
      TIME_ZONE           = "Europe/London";
      APPLICATION_PROTOCOL = "http";
      PROMETHEUS_EXPORTER_ENABLED = "false";
      PROMETHEUS_EXPORTER_HOST = "0.0.0.0";
      PROMETHEUS_EXPORTER_PORT = "9394";
      SELF_HOSTED          = "true";
      STORE_GEODATA        = "true";
    };
    extraOptions = [
      "--network=dawarich"
      "--cpus=0.5"
      "--memory=4g"
      "--health-cmd=wget -qO - http://127.0.0.1:3000/api/v1/health | grep -q '\"status\"'"
      "--health-interval=10s"
      "--health-retries=30"
      "--health-start-period=30s"
      "--health-timeout=10s"
    ];
  };

  virtualisation.oci-containers.containers.dawarich-sidekiq = {
    image = "freikin/dawarich:latest";
    dependsOn = [ "dawarich-db" "dawarich-redis" "dawarich-app" ];
    volumes = [
      "/srv/dawarich/public:/var/app/public"
      "/srv/dawarich/watched:/var/app/tmp/imports/watched"
      "/srv/dawarich/storage:/var/app/storage"
    ];
    entrypoint = "sidekiq-entrypoint.sh";
    cmd = [ "sidekiq" ];
    environment = {
      RAILS_ENV           = "development";
      REDIS_URL           = "redis://dawarich-redis:6379";
      DATABASE_HOST       = "dawarich-db";
      DATABASE_USERNAME   = "postgres";
      DATABASE_PASSWORD   = "password";
      DATABASE_NAME       = "dawarich_development";
      APPLICATION_HOSTS   = "localhost";
      BACKGROUND_PROCESSING_CONCURRENCY = "10";
      APPLICATION_PROTOCOL = "http";
      PROMETHEUS_EXPORTER_ENABLED = "false";
      PROMETHEUS_EXPORTER_HOST = "dawarich-app";
      PROMETHEUS_EXPORTER_PORT = "9394";
      SELF_HOSTED          = "true";
      STORE_GEODATA        = "true";
    };
    extraOptions = [
      "--network=dawarich"
      "--health-cmd=pgrep -f sidekiq"
      "--health-interval=10s"
      "--health-retries=30"
      "--health-start-period=30s"
      "--health-timeout=10s"
    ];
  };

  systemd.services.create-dawarich-network = {
    description = "Create Podman network for Dawarich";
    after = [ "podman.service" ];
    wantedBy = [
      "podman-dawarich-redis.service"
      "podman-dawarich-db.service"
      "podman-dawarich-app.service"
      "podman-dawarich-sidekiq.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/podman network create dawarich --ignore";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/dawarich 0755 root root -"
    "d /srv/dawarich/db 0700 root root -"
    "d /srv/dawarich/shared 0755 root root -"
    "d /srv/dawarich/public 0755 root root -"
    "d /srv/dawarich/watched 0755 root root -"
    "d /srv/dawarich/storage 0755 root root -"
  ];
}
