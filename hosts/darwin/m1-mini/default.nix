{ ... }:

{
  imports = [
    ../common
    ./muscriptor.nix
  ];

  # Apple Silicon.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "m1-mini";
}
