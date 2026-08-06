{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Unlike trigkey, this host does NOT glob all of ../optional. Those modules
  # carry no enable flags — each one turns its service on unconditionally, and
  # many are bound to trigkey's hardware (Immich mount, Garage, Newt tunnel,
  # the Incus LXC). List the wanted modules explicitly instead.
  imports = [
    ./hardware-configuration.nix
    ../common
    ../optional/monitoring/exporters.nix # node_exporter :9100, cAdvisor :9101
    ./backup-server.nix # restic REST server on the T7 external SSD

    # Deliberately NOT imported:
    #   ../optional/tailscale.nix — the sops secret tailscale/authkey is a
    #     single-use key already consumed by trigkey. Mint a second key, store
    #     it under its own sops name, then import a host-local variant.
  ];

  # ── Boot ─────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Networking ───────────────────────────────────────────────────────────────
  networking.hostName = "gmktec";
  networking.useDHCP = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── Swap ─────────────────────────────────────────────────────────────────────
  # 32 GB of RAM and no swap partition on the 1 TB SSD. zram covers the rare
  # spike without a permanent on-disk partition.
  zramSwap.enable = true;

  # ── Sudo ─────────────────────────────────────────────────────────────────────
  # Same reasoning as trigkey: single-user homelab, SSH key-only, so passwordless
  # sudo for wheel keeps remote rebuilds non-interactive.
  security.sudo.wheelNeedsPassword = false;

  # ── SSH access from trigkey ──────────────────────────────────────────────────
  # ../common authorises only the eric@ericsharma.xyz workstation key. trigkey
  # holds a different key, so add it here (host-local, not in ../common) to let
  # trigkey drive remote rebuilds of this host.
  users.users.eric.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5VwnSo02kL3IXOVayB8NGXykpqML1aysXuxX5iLhjS trigkey"
  ];

  # ── Remote deploys from trigkey ──────────────────────────────────────────────
  # `nixos-rebuild --target-host eric@gmktec` pushes an unsigned closure, which
  # the daemon refuses unless the SSH user is trusted. eric already has
  # passwordless sudo here, so this grants no new privilege.
  nix.settings.trusted-users = [
    "root"
    "eric"
  ];

  # ── State version — do not change after initial install ──────────────────────
  system.stateVersion = "25.11";
}
