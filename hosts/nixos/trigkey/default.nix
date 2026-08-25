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
    ./backup.nix
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
  networking.firewall.allowedTCPPorts = [
    22
    5757
  ];

  # ── Sudo ─────────────────────────────────────────────────────────────────────
  # Passwordless sudo for wheel on this host. Single-user homelab, SSH key-only,
  # public exposure goes through Newt/Pangolin — the practical threat-model delta
  # vs. requiring a password is small, and it lets Claude run rebuild/systemctl
  # non-interactively without handing control back for password prompts.
  security.sudo.wheelNeedsPassword = false;

  # ── SSH access from gmktec ───────────────────────────────────────────────────
  # ../common authorises only the eric@ericsharma.xyz workstation key. gmktec
  # holds a different key, so add it here to let a Claude session on gmktec ssh
  # into trigkey (mirrors the trigkey key authorised in hosts/nixos/gmktec).
  users.users.eric.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBbzujAWHoq5q6WUSqYt6sVfBp4LjrD9wm+e0kP3x14b gmktec-deploy"
  ];

  # ── Portless (LAN mDNS proxy) ────────────────────────────────────────────────
  # Each key becomes `<key>.local` on the Wi-Fi via avahi. Add a line, rebuild,
  # done. See ../optional/portless.nix for the module itself. gmktec also
  # enables portless — keep alias names distinct across hosts (see
  # docs/networking.md) so mDNS doesn't suffix one of them.
  services.portless.aliases = {
    finance = 5174;
  };

  # ── State version — do not change after initial install ──────────────────────
  system.stateVersion = "25.11";
}
