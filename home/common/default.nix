{ config, pkgs, ... }:

{
  imports = [
    ./packages.nix
    ./git.nix
    ./shell.nix
    ./nano.nix
    ./prompt.nix
  ];

  # Home Manager required settings
  home.username = "eric";
  home.homeDirectory = "/home/eric";
  home.stateVersion = "25.11";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;
}
