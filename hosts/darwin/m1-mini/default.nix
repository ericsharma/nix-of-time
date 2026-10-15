{ lib, ... }:

{
  imports = [
    ../common
    ../optional/claude-adhd.nix
    ./llama-server.nix
    ./muscriptor.nix
    ./sops.nix
  ];

  # Apple Silicon.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "m1-mini";

  # This mini's local account is "ericsharma", not "eric" (the default set in
  # ../common for the other darwin hosts) — override both so primaryUser
  # validation and muscriptor.nix's ${home} resolve to a real account.
  # mkForce: ../common already defines primaryUser at normal priority, so a
  # plain override here would conflict rather than win.
  system.primaryUser = lib.mkForce "ericsharma";
  users.users.ericsharma.home = "/Users/ericsharma";

  # trigkey's tmux windows ssh here (ericsharma@192.168.0.5). Key login lets
  # those windows reconnect without a password, and lets the E.T. iOS app
  # forward uploaded screenshots from trigkey to this machine.
  users.users.ericsharma.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5VwnSo02kL3IXOVayB8NGXykpqML1aysXuxX5iLhjS trigkey"
  ];
}
