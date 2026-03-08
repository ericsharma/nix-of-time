{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../common
    ./containers.nix
    ./newt.nix
    ./immich.nix
    ./garage.nix
    ./garage-webui.nix
    ./services/kavita.nix
    ./services/memos.nix
    ./services/scrobbler.nix
    ./services/networking-tools.nix
    ./services/strava.nix
    ./services/koito.nix
    # ./services/karakeep.nix    # TODO: enable after data migration
    # ./services/dawarich.nix    # TODO: enable after data migration
  ];

  # ── Boot ─────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Networking ───────────────────────────────────────────────────────────────
  networking.hostName = "trigkey";
  networking.useDHCP  = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall.enable          = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── State version — do not change after initial install ──────────────────────
  system.stateVersion = "25.11";
}
