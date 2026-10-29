{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    nodejs_22
    claude-code
    grok-build
    antigravity-cli

    pai-sho

    # Utilities
    media-to-ascii
    ripgrep
    fd
    jq
    tree
  ];
}
