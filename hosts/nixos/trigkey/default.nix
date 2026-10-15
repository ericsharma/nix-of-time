{
  config,
  lib,
  pkgs,
  inventory,
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
    ./kavita-nfs.nix

    # Deliberately NOT imported:
    #   ./nxbt.nix — Bluetooth Switch controller, off since 2026-10-08. The
    #     wired board on gmktec replaced it, and its kernel patch makes trigkey
    #     build its own kernel. To turn it on: docs/services/nxbt.md.
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

  # ── Extra SSH keys ───────────────────────────────────────────────────────────
  # ../common authorises only the eric@ericsharma.xyz workstation key; these
  # are trigkey-only additions, merged with it.
  users.users.eric.openssh.authorizedKeys.keys = [
    # gmktec holds a different key; lets a Claude session on gmktec ssh into
    # trigkey (mirrors the trigkey key authorised in hosts/nixos/gmktec).
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBbzujAWHoq5q6WUSqYt6sVfBp4LjrD9wm+e0kP3x14b gmktec-deploy"
    # E.T. iOS tmux client on Eric's iPhone. Secure Enclave key: it can't
    # leave the phone. Revoke by deleting this line.
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBA6aXpSJrlSs8thqORjHOnwu0J1lPknOTr2ubyISJ4ppS4Mshgeof2fvUvmCB1wgf13cNlumVR2Ph3/4T7TBS4I= E.T.@iPhone"
  ];

  # ── Portless (LAN mDNS proxy) ────────────────────────────────────────────────
  # Each key becomes `<key>.local` on the Wi-Fi via avahi. See
  # ../optional/portless.nix for the module itself.
  #
  # The names are declared in inventory.nix, not here, because monitoring.nix
  # reads the same map to build a blackbox probe per alias — one edit there
  # adds the name and its dashboard row together. Add an alias in
  # inventory.nix, rebuild both hosts, done.
  services.portless.aliases = inventory.hosts.trigkey.portlessAliases;

  # ── State version — do not change after initial install ──────────────────────
  system.stateVersion = "25.11";
}
