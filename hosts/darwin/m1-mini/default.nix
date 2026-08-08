{ ... }:

{
  imports = [
    ../common
    ./muscriptor.nix
  ];

  # Apple Silicon.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "m1-mini";

  # This mini's local account is "ericsharma", not "eric" (the default set in
  # ../common for the other darwin hosts) — override both so primaryUser
  # validation and muscriptor.nix's ${home} resolve to a real account.
  system.primaryUser = "ericsharma";
  users.users.ericsharma.home = "/Users/ericsharma";
}
