{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Pull in every *.nix under hosts/optional/. trigkey opts into the entire
  # shared library; future hosts can import a subset by listing files manually.
  optionalModules = lib.filter (p: lib.hasSuffix ".nix" (toString p)) (
    lib.filesystem.listFilesRecursive ../optional
  );
in
{
  imports = optionalModules ++ [
    ./hardware-configuration.nix
    ../common
    ./containers.nix
    ./newt.nix
    ./immich.nix
    ./garage.nix
    ./garage-webui.nix
    ./eric-portfolio-backfill.nix
  ];

  # ── Boot ─────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Networking ───────────────────────────────────────────────────────────────
  networking.hostName = "trigkey";
  networking.useDHCP = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── Sudo ─────────────────────────────────────────────────────────────────────
  # Passwordless sudo for wheel on this host. Single-user homelab, SSH key-only,
  # public exposure goes through Newt/Pangolin — the practical threat-model delta
  # vs. requiring a password is small, and it lets Claude run rebuild/systemctl
  # non-interactively without handing control back for password prompts.
  security.sudo.wheelNeedsPassword = false;

  # ── pai-sho — dev tunnel (no open ports, peer-to-peer via iroh) ─────────────
  # Get ticket after rebuild: journalctl -u pai-sho | grep "Ticket:"
  # Laptop: pai-sho daemon -a <ticket>   (macOS: brew install cablehead/tap/pai-sho)
  services.pai-sho = {
    enable = true;
    exposedPorts = [ ]; # add service ports you want to reach from laptop
  };

  # ── State version — do not change after initial install ──────────────────────
  system.stateVersion = "25.11";
}
