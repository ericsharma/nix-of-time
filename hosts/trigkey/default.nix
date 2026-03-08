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
