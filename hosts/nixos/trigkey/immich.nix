{ ... }:

{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    mediaLocation = "/mnt/immich-data/immich";
  };

  # NixOS 26.05 marks Immich 2.x insecure: 2.x gets no more updates, and
  # Immich 3 is only in nixos-unstable. 2.7.5 is the version that already
  # runs here, so allowing it keeps Immich as it was before the 26.05 bump.
  # Moving to Immich 3 (pkgs.unstable.immich) is a separate upgrade with
  # database migrations. The exact version string makes eval fail again on
  # any other 2.x, so the exception has to be looked at again.
  nixpkgs.config.permittedInsecurePackages = [ "immich-2.7.5" ];

  # immich-machine-learning needs python imageio (through insightface,
  # albumentations, scikit-image). On nixos-26.05 two imageio tests fail
  # against its Pillow ("Invalid mode for data type"), so the package has no
  # binary cache entry and the local build stops. The two tests check 16-bit
  # PNG handling in the pillow plugin, which Immich does not use. Remove this
  # overlay when imageio builds on 26.05 again.
  nixpkgs.overlays = [
    (_final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (_pyfinal: pyprev: {
          imageio = pyprev.imageio.overridePythonAttrs (old: {
            disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
              "tests/test_pillow.py::test_png_16bit"
              "tests/test_pillow_legacy.py::test_png"
            ];
          });
        })
      ];
    })
  ];

  # The disk is mounted `nofail` (hardware-configuration.nix). If it is late or
  # unplugged, Immich must not start and write a new library onto the root
  # filesystem under the empty mountpoint.
  systemd.services.immich-server.unitConfig.RequiresMountsFor = "/mnt/immich-data";
}
