{ ... }:

{
  imports = [
    ../common
    ../optional/claude-gstack.nix
    ../optional/claude-adhd.nix
    ./tmux-persist.nix
  ];

  # Host-specific overrides can go here
}
