{ config, ... }:

{
  # ── Koito (custom app + Postgres) ────────────────────────────────────────────
  # Data dirs: /srv/koito/{data,db}
  # Port: 4110

  sops.secrets."koito/env" = {};

  virtualisation.oci-containers.containers.koito-db = {
    image = "postgres:16";
    ports = [ "127.0.0.1:5433:5432" ];
    volumes = [
      "/srv/koito/db:/var/lib/postgresql/data"
    ];
    environmentFiles = [
      config.sops.secrets."koito/env".path
    ];
    extraOptions = [
      "--health-cmd=pg_isready -U postgres -d koitodb"
      "--health-interval=5s"
      "--health-timeout=5s"
      "--health-retries=5"
    ];
  };

  virtualisation.oci-containers.containers.koito = {
    image = "gabehf/koito:latest";
    dependsOn = [ "koito-db" ];
    ports = [ "127.0.0.1:4110:4110" ];
    volumes = [
      "/srv/koito/data:/etc/koito"
    ];
    environmentFiles = [
      config.sops.secrets."koito/env".path
    ];
    extraOptions = [ "--network=host" ];
  };

  # Wait for Postgres to be healthy before starting koito
  systemd.services.podman-koito.preStart = ''
    until /run/current-system/sw/bin/podman healthcheck run koito-db; do
      sleep 2
    done
  '';

  # DB dump restore (run once after migration):
  #   sudo podman cp /tmp/koito.sql koito-db:/tmp/koito.sql
  #   sudo podman exec koito-db psql -U postgres -d koitodb -f /tmp/koito.sql

  systemd.tmpfiles.rules = [
    "d /srv/koito 0755 root root -"
    "d /srv/koito/data 0755 root root -"
    "d /srv/koito/db 0755 root root -"
  ];
}
