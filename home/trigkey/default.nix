{ ... }:

{
  imports = [
    ../common
    ../optional/claude-gstack.nix
    ../optional/claude-adhd.nix
    ./tmux-persist.nix
    ./et-notify.nix
  ];

  # Host-specific overrides can go here
}
