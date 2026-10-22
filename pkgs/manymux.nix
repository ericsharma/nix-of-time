{
  lib,
  rustPlatform,
  src,
}:

# manymux (https://github.com/rayfish/manymux): persistent terminal sessions on
# every machine, from the `manymux` flake input (one pinned release). The E.T.
# iOS app reaches these sessions through etd on trigkey; see
# home/optional/manymux.nix and ~/et-ios/docs/PLAN-manymux.md.
#
# A bump changes trigkey, gmktec and m1-mini, and et-link in the etd repo must
# move to the same commit. A new binary only takes effect after a node restart,
# which ends every session: restart by hand with `mm update --keep-sessions`.
rustPlatform.buildRustPackage {
  pname = "manymux";
  version = (lib.importTOML "${src}/Cargo.toml").package.version;
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";
  # build.rs reads the commit from git, which the Nix sandbox does not have.
  env.MM_COMMIT = builtins.substring 0 8 src.rev;
  cargoBuildFlags = [
    "--bin"
    "mm"
  ];
  # The end-to-end tests drive a stub ssh and real PTYs; upstream CI runs them.
  doCheck = false;
  meta = {
    description = "Persistent terminal sessions across SSH hosts";
    homepage = "https://github.com/rayfish/manymux";
    license = lib.licenses.mpl20;
    mainProgram = "mm";
  };
}
