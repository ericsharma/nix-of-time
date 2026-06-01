{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    nodejs_22
    claude-code
    grok-build

    pai-sho

    # Utilities
    ripgrep
    fd
    jq
    tree
  ];
}
