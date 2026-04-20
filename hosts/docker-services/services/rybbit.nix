{ config, ... }:

# Rybbit — self-hosted web analytics, wired for Pangolin.
# Reference: https://rybbit.com/docs/self-hosting-guides/pangolin
#
# No Caddy, no in-network Newt: USE_WEBSERVER=false and the backend/client
# ports are exposed to the LXC. Trigkey's host-level Newt (hosts/trigkey/
# newt.nix) routes Pangolin traffic to 10.0.100.10:{3001,3002}.
#
# Pangolin dashboard setup required (configure in the Pangolin UI):
#   Client resource  → target: 10.0.100.10, port: 3002
#   Backend resource → target: 10.0.100.10, port: 3001
#   Both resources MUST set these headers:
#     X-Forwarded-Proto: https
#     X-Forwarded-Host:  <DOMAIN_NAME>
#   Without them, client→backend API calls fail CORS/origin checks.

let
  domain  = "tracking.ericsharma.xyz";
  baseUrl = "https://${domain}";

  sharedDbEnv = {
    POSTGRES_DB    = "analytics";
    POSTGRES_HOST  = "postgres";
    CLICKHOUSE_DB  = "analytics";
    CLICKHOUSE_HOST = "http://clickhouse:8123";
  };
in
{
  virtualisation.oci-containers.containers = {

    rybbit-clickhouse = {
      image   = "clickhouse/clickhouse-server:25.4.2";
      volumes = [ "/srv/rybbit/clickhouse:/var/lib/clickhouse" ];
      environmentFiles = [ config.sops.secrets."docker-services/rybbit/env".path ];
      environment = { CLICKHOUSE_DB = sharedDbEnv.CLICKHOUSE_DB; };
      extraOptions = [
        "--network=rybbit"
        "--network-alias=clickhouse"
        "--ulimit=nofile=262144:262144"
        "--health-cmd=wget -qO- http://127.0.0.1:8123/ping || exit 1"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

    rybbit-postgres = {
      image   = "postgres:17.4";
      volumes = [ "/srv/rybbit/postgres:/var/lib/postgresql/data" ];
      environmentFiles = [ config.sops.secrets."docker-services/rybbit/env".path ];
      environment = { POSTGRES_DB = sharedDbEnv.POSTGRES_DB; };
      extraOptions = [
        "--network=rybbit"
        "--network-alias=postgres"
        "--health-cmd=pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

    rybbit-backend = {
      image = "ghcr.io/rybbit-io/rybbit-backend:latest";
      ports = [ "3001:3001" ];
      environmentFiles = [ config.sops.secrets."docker-services/rybbit/env".path ];
      environment = sharedDbEnv // {
        USE_WEBSERVER = "false";
        DOMAIN_NAME   = domain;
        BASE_URL      = baseUrl;
        DISABLE_TELEMETRY = "true";
      };
      dependsOn = [ "rybbit-clickhouse" "rybbit-postgres" ];
      extraOptions = [
        "--network=rybbit"
        "--health-cmd=wget -qO- http://127.0.0.1:3001/api/health || exit 1"
        "--health-interval=10s"
        "--health-timeout=5s"
        "--health-retries=10"
        "--health-start-period=30s"
      ];
    };

    rybbit-client = {
      image = "ghcr.io/rybbit-io/rybbit-client:latest";
      ports = [ "3002:3002" ];
      environmentFiles = [ config.sops.secrets."docker-services/rybbit/env".path ];
      environment = {
        NEXT_PUBLIC_BACKEND_URL = baseUrl;
        NEXT_PUBLIC_DISABLE_SIGNUP = "false";
      };
      dependsOn = [ "rybbit-backend" ];
      extraOptions = [ "--network=rybbit" ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-rybbit-clickhouse.preStart = ''
    docker network create rybbit 2>/dev/null || true
  '';

  # ── Wait for DBs healthy before starting backend ──────────────────────────
  systemd.services.docker-rybbit-backend.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' rybbit-clickhouse 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
    until docker inspect --format '{{.State.Health.Status}}' rybbit-postgres 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';

  # ── Wait for backend healthy before starting client ───────────────────────
  systemd.services.docker-rybbit-client.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' rybbit-backend 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';
}
