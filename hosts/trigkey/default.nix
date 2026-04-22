{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../common
    ../optional/incus.nix
    ../optional/podman.nix
    ../optional/vaultwarden.nix
    ../optional/monitoring/exporters.nix
    ../optional/homeassistant.nix
    ../optional/monitoring.nix
    ../optional/syncthing.nix
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
    ./services/pirousync.nix
    ./services/belle-watson-studios.nix
    ./services/strava.nix
    ./services/tapmap.nix
    ./services/termix.nix
    ./services/whisper-transcription.nix
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
