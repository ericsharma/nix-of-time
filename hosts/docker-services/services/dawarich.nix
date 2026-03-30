{ config, ... }:

let
  sharedEnv = {
    RAILS_ENV                        = "development";
    REDIS_URL                        = "redis://dawarich-redis:6379";
    DATABASE_HOST                    = "dawarich-db";
    DATABASE_NAME                    = "dawarich_development";
    DATABASE_USERNAME                = "postgres";
    APPLICATION_HOSTS                = "localhost,d.ericsharma.xyz";
    APPLICATION_PROTOCOL             = "http";
    PROMETHEUS_EXPORTER_ENABLED      = "false";
    PROMETHEUS_EXPORTER_HOST         = "0.0.0.0";
    PROMETHEUS_EXPORTER_PORT         = "9394";
    SELF_HOSTED                      = "true";
    STORE_GEODATA                    = "true";
  };
in
{
  virtualisation.oci-containers.containers = {

    dawarich-redis = {
      image   = "redis:7.4-alpine";
      cmd     = [ "redis-server" ];
      volumes = [ "/srv/dawarich/shared:/data" ];
      extraOptions = [
        "--network=dawarich"
        "--health-cmd=redis-cli --raw incr ping"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

    dawarich-db = {
      image   = "postgis/postgis:17-3.5-alpine";
      volumes = [
        "/srv/dawarich/db:/var/lib/postgresql/data"
        "/srv/dawarich/shared:/var/shared"
      ];
      environmentFiles = [ config.sops.secrets."docker-services/dawarich/env".path ];
      environment = { POSTGRES_DB = "dawarich_development"; };
      extraOptions = [
        "--network=dawarich"
        "--shm-size=1g"
        "--health-cmd=pg_isready -U postgres -d dawarich_development"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

    dawarich-app = {
      image       = "freikin/dawarich:1.6.0";
      entrypoint  = "web-entrypoint.sh";
      cmd         = [ "bin/rails" "server" "-p" "3000" "-b" "::" ];
      ports       = [ "3000:3000" ];
      volumes     = [
        "/srv/dawarich/public:/var/app/public"
        "/srv/dawarich/watched:/var/app/tmp/imports/watched"
        "/srv/dawarich/storage:/var/app/storage"
        "/srv/dawarich/db:/dawarich_db_data"
      ];
      environmentFiles = [ config.sops.secrets."docker-services/dawarich/env".path ];
      environment  = sharedEnv // {
        MIN_MINUTES_SPENT_IN_CITY = "60";
        TIME_ZONE                 = "Europe/London";
      };
      dependsOn    = [ "dawarich-db" "dawarich-redis" ];
      extraOptions = [
        "--network=dawarich"
        "--health-cmd=wget -qO - http://127.0.0.1:3000/api/v1/health | grep -q '\"status\":\"ok\"'"
        "--health-interval=10s"
        "--health-timeout=10s"
        "--health-retries=30"
        "--health-start-period=30s"
      ];
    };

    dawarich-sidekiq = {
      image      = "freikin/dawarich:1.6.0";
      entrypoint = "sidekiq-entrypoint.sh";
      cmd        = [ "sidekiq" ];
      volumes    = [
        "/srv/dawarich/public:/var/app/public"
        "/srv/dawarich/watched:/var/app/tmp/imports/watched"
        "/srv/dawarich/storage:/var/app/storage"
      ];
      environmentFiles = [ config.sops.secrets."docker-services/dawarich/env".path ];
      environment  = sharedEnv // {
        BACKGROUND_PROCESSING_CONCURRENCY = "10";
        PROMETHEUS_EXPORTER_HOST          = "dawarich-app";
      };
      dependsOn    = [ "dawarich-db" "dawarich-redis" "dawarich-app" ];
      extraOptions = [
        "--network=dawarich"
        "--health-cmd=pgrep -f sidekiq"
        "--health-interval=10s"
        "--health-retries=30"
        "--health-start-period=30s"
      ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-dawarich-redis.preStart = ''
    docker network create dawarich 2>/dev/null || true
  '';

  # ── Wait for DB + Redis healthy before starting app ───────────────────────
  systemd.services.docker-dawarich-app.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' dawarich-db 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
    until docker inspect --format '{{.State.Health.Status}}' dawarich-redis 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';

  # ── Wait for app healthy before starting sidekiq ─────────────────────────
  systemd.services.docker-dawarich-sidekiq.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' dawarich-app 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';
}
