{ config, ... }:

{
  # ── Koito (custom app + Postgres) ────────────────────────────────────────────
  # Data dirs: /srv/koito/{data,db}
  # Port: 4110

  sops.secrets."koito/env" = {};

  virtualisation.oci-containers.containers.koito-db = {
    image = "postgres:16";
    volumes = [
      "/srv/koito/db:/var/lib/postgresql/data"
    ];
    environmentFiles = [
      config.sops.secrets."koito/env".path
    ];
    extraOptions = [ "--network=koito" "--health-cmd=pg_isready -U postgres -d koitodb"
                     "--health-interval=5s" "--health-timeout=5s" "--health-retries=5" ];
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
    extraOptions = [ "--network=koito" ];
  };

  # Create the Podman network for inter-container communication
  systemd.services.create-koito-network = {
    description = "Create Podman network for Koito";
    after = [ "podman.service" ];
    wantedBy = [ "podman-koito-db.service" "podman-koito.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/podman network create koito --ignore";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/koito 0755 root root -"
    "d /srv/koito/data 0755 root root -"
    "d /srv/koito/db 0755 root root -"
  ];
}
