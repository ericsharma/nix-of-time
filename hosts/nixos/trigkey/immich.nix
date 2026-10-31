{ ... }:

{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    mediaLocation = "/mnt/immich-data/immich";
  };

  # The disk is mounted `nofail` (hardware-configuration.nix). If it is late or
  # unplugged, Immich must not start and write a new library onto the root
  # filesystem under the empty mountpoint.
  systemd.services.immich-server.unitConfig.RequiresMountsFor = "/mnt/immich-data";
}
