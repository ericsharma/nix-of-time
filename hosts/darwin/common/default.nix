{ pkgs, ... }:

{
  # ── Nix daemon ───────────────────────────────────────────────────────────────
  # Flakes + nix-command are on for every other host in this repo. Keep parity
  # so darwin-rebuild doesn't need --extra-experimental-features on every call.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Some newer nix-darwin options (activation script user context, user
  # LaunchAgents rendered to $HOME) refuse to evaluate without a declared
  # primary user. Matches the single-user pattern used on every host here.
  system.primaryUser = "eric";
  users.users.eric.home = "/Users/eric";

  # All darwin hosts are bootstrapped with the Determinate Nix installer,
  # which runs its own daemon and manages the Nix install itself. Letting
  # nix-darwin also try to manage it makes activation refuse to run.
  nix.enable = false;

  # macOS ships BSD variants of these; putting the nixpkgs versions on PATH
  # avoids "same command, different flags" surprises across Linux and darwin
  # hosts.
  environment.systemPackages = with pkgs; [
    coreutils
    curl
    git
    gnused
  ];

  nixpkgs.config.allowUnfree = true;

  # nix-darwin state version. Bump only when the release notes call for it.
  system.stateVersion = 5;
}
