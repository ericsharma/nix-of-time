{ ... }:

{
  imports = [
    ../common
    ../optional/claude-gstack.nix
    ../optional/claude-adhd.nix
    ../optional/claude-skills.nix
    ./tmux-persist.nix
    ./workspace.nix
    ./et-notify.nix
  ];

  # Host-specific overrides can go here
}
