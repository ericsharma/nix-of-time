{ config, ... }:

{
  virtualisation.oci-containers.containers = {

    koito-db = {
      image   = "postgres:16";
      volumes = [ "/srv/koito/db:/var/lib/postgresql/data" ];
      environmentFiles = [ config.sops.secrets."docker-services/koito/env".path ];
      extraOptions = [
        "--network=koito"
        "--health-cmd=pg_isready -U postgres -d koitodb"
        "--health-interval=5s"
        "--health-timeout=5s"
        "--health-retries=5"
      ];
    };

    koito = {
      image   = "gabehf/koito:latest";
      ports   = [ "4110:4110" ];
      volumes = [ "/srv/koito/data:/etc/koito" ];
      environmentFiles = [ config.sops.secrets."docker-services/koito/env".path ];
      dependsOn   = [ "koito-db" ];
      extraOptions = [ "--network=koito" ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-koito-db.preStart = ''
    docker network create koito 2>/dev/null || true
  '';

  # ── Wait for DB healthy before starting app ───────────────────────────────
  systemd.services.docker-koito.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' koito-db 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';
}
