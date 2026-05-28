{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Development tools
    nodejs_22
    claude-code

    # Utilities
    ripgrep
    fd
    jq
    tree
  ];
}
