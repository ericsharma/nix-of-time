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
    ../optional/tailscale.nix
    ./containers.nix
    ./newt.nix
    ./immich.nix
    ./garage.nix
    ./garage-webui.nix
    ../optional/komodo.nix
    ../optional/kavita.nix
    ../optional/memos.nix
    ../optional/scrobbler.nix
    ../optional/networking-tools.nix
    ../optional/pirousync.nix
    ../optional/pirousync-dev.nix
    ../optional/belle-watson-studios.nix
    ../optional/strava.nix
    ../optional/tapmap.nix
    ../optional/termix.nix
    ../optional/whisper-transcription.nix
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
