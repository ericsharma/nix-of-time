{ ... }:

{
  imports = [
    ../common
    ../optional/claude-gstack.nix
    ../optional/claude-adhd.nix
    ../optional/claude-skills.nix
    ./tmux-persist.nix
    ./workspace.nix
    ./manymux-checkpoint.nix
    ./et-notify.nix
    ./etd.nix
    ../optional/manymux.nix
  ];

  # Host-specific overrides can go here
}
