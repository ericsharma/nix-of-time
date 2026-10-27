{
  lib,
  modulesPath,
  ...
}:

# RackNerd VPS: the public edge. Runs the Pangolin stack and nothing else.
# Not on the LAN and not a homelab peer — see docs/fleet/racknerd.md.
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
    ../common
    ../optional/podman.nix # oci-containers backend for the Pangolin stack
    ./pangolin.nix # Pangolin + Gerbil + Traefik on :80, :443, :51820/udp
  ];

  # ── Secrets ──────────────────────────────────────────────────────────────────
  # Its own file, encrypted to personal + trigkey + this host only. This is the
  # most exposed machine in the fleet: it must not hold the age key that opens
  # secrets/secrets.yaml (every homelab secret).
  sops.defaultSopsFile = lib.mkForce ../../../secrets/racknerd.yaml;

  # ── Boot ─────────────────────────────────────────────────────────────────────
  # BIOS + GPT: disko points GRUB at the EF02 partition in disk-config.nix.
  boot.loader.grub.enable = true;

  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────────────────
  networking.hostName = "racknerd";
  # RackNerd hands out the public /26 address by DHCP (Ubuntu's netplan used
  # dhcp4 too). No static config to drift from the panel.
  networking.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
  # The Pangolin ports are published by Podman (DNAT), so they bypass the INPUT
  # chain; they are listed in pangolin.nix anyway, as the record of what is open.

  # ── SSH ──────────────────────────────────────────────────────────────────────
  # Deploys run as root from trigkey (nixos-rebuild --target-host root@…), key
  # only. eric keeps a sudo password: etd runs as eric, and every etd network
  # member can run commands as eric — that must not be root here.
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5VwnSo02kL3IXOVayB8NGXykpqML1aysXuxX5iLhjS trigkey"
  ];
  users.users.eric.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5VwnSo02kL3IXOVayB8NGXykpqML1aysXuxX5iLhjS trigkey"
  ];

  system.stateVersion = "25.11";
}
