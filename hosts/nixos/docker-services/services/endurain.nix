{ config, ... }:

# ── Endurain ─────────────────────────────────────────────────────────────────
# Self-hosted fitness tracking app with a native Garmin Connect integration
# (polls for new activities hourly, body composition every 4h).
# Upstream: https://codeberg.org/endurain-project/endurain
#
# Port: 8080 (inside the LXC; reached as 10.0.100.10:8080)
# Data: /srv/endurain/{postgres,redis,data,logs}  (host: /srv/docker-services/endurain)
#
# NOT backed up — and this is now load-bearing, not an evaluation instance: it
# is the source of truth for new activities, which dreeve consumes as .fit files
# (see optional/dreeve.nix). Its Postgres holds activity data that exists
# nowhere else. Needs /srv/docker-services/endurain in restic plus a pg_dump
# timer — the raw Postgres dir is not a clean backup.
#
# Garmin credentials are sent frontend→backend in plaintext, so this must be
# reached over HTTPS (Pangolin) before linking an account — never over :8080.

let
  image = "codeberg.org/endurain-project/endurain:v0.18.3";
in
{
  virtualisation.oci-containers.containers = {

    endurain-postgres = {
      image = "postgres:18";
      volumes = [ "/srv/endurain/postgres:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_DB = "endurain";
        POSTGRES_USER = "endurain";
        PGDATA = "/var/lib/postgresql/data/pgdata";
      };
      environmentFiles = [ config.sops.secrets."docker-services/endurain/env".path ];
      extraOptions = [
        "--network=endurain"
        "--health-cmd=pg_isready -U endurain"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    endurain-redis = {
      image = "redis:8-alpine";
      cmd = [
        "redis-server"
        "--appendonly"
        "yes"
      ];
      volumes = [ "/srv/endurain/redis:/data" ];
      extraOptions = [
        "--network=endurain"
        "--health-cmd=redis-cli ping"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    endurain = {
      inherit image;
      ports = [ "8080:8080" ];
      volumes = [
        "/srv/endurain/data:/app/backend/data"
        "/srv/endurain/logs:/app/backend/logs"
      ];
      environment = {
        TZ = "America/New_York";
        ENDURAIN_HOST = "https://endurain.ericsharma.xyz";
        BEHIND_PROXY = "true";
        # Defaults to [] in production, which breaks client-IP detection (and
        # therefore rate limiting / auth security) behind a proxy. Newt runs on
        # trigkey and reaches this LXC over incusbr0, so it arrives as 10.0.100.1.
        TRUSTED_PROXIES = "10.0.100.1";
        # Upstream defaults assume compose service names; our containers are
        # prefixed to avoid colliding with the other stacks in this LXC.
        DB_HOST = "endurain-postgres";
        DB_USER = "endurain";
        DB_DATABASE = "endurain";
        RATE_LIMIT_STORAGE_URI = "redis://endurain-redis:6379/0";
        AUTH_SECURITY_STORAGE_URI = "redis://endurain-redis:6379/0";
      };
      environmentFiles = [ config.sops.secrets."docker-services/endurain/env".path ];
      dependsOn = [
        "endurain-postgres"
        "endurain-redis"
      ];
      extraOptions = [ "--network=endurain" ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-endurain-postgres.preStart = ''
    docker network create endurain 2>/dev/null || true
  '';

  # ── Wait for DB + redis healthy before starting app ───────────────────────
  systemd.services.docker-endurain.preStart = ''
    for c in endurain-postgres endurain-redis; do
      until docker inspect --format '{{.State.Health.Status}}' "$c" 2>/dev/null | grep -q "healthy"; do
        sleep 2
      done
    done
  '';
}
