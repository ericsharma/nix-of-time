{ ... }:

{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    mediaLocation = "/mnt/immich-data/immich";
  };
}
