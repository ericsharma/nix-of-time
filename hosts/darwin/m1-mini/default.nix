{ lib, ... }:

{
  imports = [
    ../common
    ../optional/claude-adhd.nix
    ../optional/claude-skills.nix
    ../optional/manymux.nix
    ../optional/etd.nix
    ./kokoro-tts.nix
    ./llama-embed.nix
    ./llama-server.nix
    ./muscriptor.nix
    ./omnivoice.nix
    ./sops.nix
  ];

  # Apple Silicon.
  nixpkgs.hostPlatform = "aarch64-darwin";

  networking.hostName = "m1-mini";

  # Headless inference box: LAN callers (nam-shub on trigkey) expect the
  # llama-server ports to answer at any hour. Equivalent to
  # `pmset -a sleep 0 disksleep 0`. Display sleep stays at the macOS default.
  power.sleep.computer = "never";
  power.sleep.harddisk = "never";
  # Come back by itself after a power cut; the daemons are RunAtLoad.
  power.restartAfterPowerFailure = true;

  # This mini's local account is "ericsharma", not "eric" (the default set in
  # ../common for the other darwin hosts) — override both so primaryUser
  # validation and muscriptor.nix's ${home} resolve to a real account.
  # mkForce: ../common already defines primaryUser at normal priority, so a
  # plain override here would conflict rather than win.
  system.primaryUser = lib.mkForce "ericsharma";
  users.users.ericsharma.home = "/Users/ericsharma";

  # No ssh key for trigkey any more (removed 2026-10-22): trigkey and the
  # E.T. app reach this machine through the etd network (./../optional/etd.nix),
  # and this machine deploys itself (darwin-rebuild here).
}
