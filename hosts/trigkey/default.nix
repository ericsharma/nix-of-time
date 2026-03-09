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
    ./services/komodo.nix
    ./services/kavita.nix
    ./services/memos.nix
    ./services/scrobbler.nix
    ./services/networking-tools.nix
    ./services/strava.nix
    # Multi-container stacks run inside the docker-services Incus container
    # ./services/koito.nix
    # ./services/karakeep.nix
    # ./services/dawarich.nix
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
