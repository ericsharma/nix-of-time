{
  lib,
  ...
}:

# Base for the RackNerd VPSs that are (or will be) Pangolin nodes: the public
# edge. Not on the LAN and not homelab peers — see docs/fleet/pangolin-nodes.md.
# The stack itself is ./pangolin.nix, imported by the host that runs it.
{
  imports = [ ../common ];

  # ── Secrets ──────────────────────────────────────────────────────────────────
  # Their own file, encrypted to personal + trigkey + the nodes only. These are
  # the most exposed machines in the fleet: they must not hold an age key that
  # opens secrets/secrets.yaml (every homelab secret).
  sops.defaultSopsFile = lib.mkForce ../../../secrets/pangolin.yaml;

  # ── Boot ─────────────────────────────────────────────────────────────────────
  # BIOS + GPT: GRUB's core goes in vda1 (each host's hardware-configuration.nix).
  boot.loader.grub.enable = true;

  zramSwap.enable = true;

  # ── Networking ───────────────────────────────────────────────────────────────
  # RackNerd hands out the public address by DHCP (Ubuntu's netplan used dhcp4
  # too). No static config to drift from the panel.
  networking.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

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
