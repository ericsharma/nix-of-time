{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    nodejs_22
    claude-code
    grok-build

    pai-sho

    # Utilities
    media-to-ascii
    ripgrep
    fd
    jq
    tree
  ];
}
