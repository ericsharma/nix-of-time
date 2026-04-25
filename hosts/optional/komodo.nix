{ config, ... }:

{
  # ── Komodo (container management) ────────────────────────────────────────────
  # MongoDB on 127.0.0.1:27017, Core on 127.0.0.1:9120
  # Periphery agents run on managed servers (e.g. docker-services Incus container)

  sops.secrets."komodo/env" = {};

  # ── MongoDB ───────────────────────────────────────────────────────────────────
  virtualisation.oci-containers.containers.komodo-mongo = {
    image = "mongo";
    ports = [ "127.0.0.1:27017:27017" ];
    cmd = [ "--quiet" "--wiredTigerCacheSizeGB" "0.25" ];
    volumes = [
      "/srv/komodo/mongo-data:/data/db"
      "/srv/komodo/mongo-config:/data/configdb"
    ];
    environmentFiles = [ config.sops.secrets."komodo/env".path ];
    labels = { "komodo.skip" = ""; };
    extraOptions = [
      "--health-cmd=mongosh --eval 'db.runCommand({ ping: 1 })' --quiet"
      "--health-interval=10s"
      "--health-timeout=5s"
      "--health-retries=5"
      "--health-start-period=30s"
    ];
  };

  # ── Komodo Core ───────────────────────────────────────────────────────────────
  virtualisation.oci-containers.containers.komodo-core = {
    image = "ghcr.io/moghtech/komodo-core:latest";
    dependsOn = [ "komodo-mongo" ];
    ports = [ "127.0.0.1:9120:9120" ];
    volumes = [
      "/srv/komodo/backups:/backups"
    ];
    environmentFiles = [ config.sops.secrets."komodo/env".path ];
    labels = { "komodo.skip" = ""; };
    extraOptions = [ "--network=host" ];
  };

  # Wait for MongoDB to be healthy before starting Core
  systemd.services.podman-komodo-core.preStart = ''
    until /run/current-system/sw/bin/podman healthcheck run komodo-mongo; do
      sleep 2
    done
  '';

  systemd.tmpfiles.rules = [
    "d /srv/komodo 0755 root root -"
    "d /srv/komodo/mongo-data 0755 root root -"
    "d /srv/komodo/mongo-config 0755 root root -"
    "d /srv/komodo/backups 0755 root root -"
  ];
}
