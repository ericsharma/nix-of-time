{ config, ... }:

{
  virtualisation.oci-containers.containers.periphery = {
    image = "ghcr.io/moghtech/komodo-periphery:latest";
    ports = [ "8120:8120" ];
    environmentFiles = [ config.sops.secrets."docker-services/periphery/env".path ];
    environment = {
      PERIPHERY_ROOT_DIRECTORY    = "/etc/komodo";
      PERIPHERY_SSL_ENABLED       = "true";
      PERIPHERY_DISABLE_TERMINALS = "false";
      PERIPHERY_INCLUDE_DISK_MOUNTS = "/etc/hostname";
    };
    volumes = [
      "/run/docker.sock:/var/run/docker.sock"
      "/proc:/proc"
      "/etc/komodo:/etc/komodo"
    ];
    labels = { "komodo.skip" = ""; };
  };
}
