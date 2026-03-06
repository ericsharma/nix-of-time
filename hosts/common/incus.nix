{ config, lib, pkgs, ... }:

{
  # ── Incus (containers + VMs) ──────────────────────────────────────────────
  virtualisation.incus.enable = true;

  # Incus requires nftables (not iptables)
  networking.nftables.enable = true;

  # KVM support for VMs (kvm-amd already loaded in hardware-configuration.nix)
  virtualisation.libvirtd.enable = true;

  users.users.eric.extraGroups = [ "incus-admin" ];

  # Allow incus bridge traffic through the firewall
  networking.firewall.trustedInterfaces = [ "incusbr0" ];

  # ── Preseed: storage, networking, default profile ─────────────────────────
  virtualisation.incus.preseed = {
    networks = [{
      name   = "incusbr0";
      type   = "bridge";
      config = {
        "ipv4.address" = "10.0.100.1/24";
        "ipv4.nat"     = "true";
        "ipv6.address" = "none";
      };
    }];

    storage_pools = [{
      name   = "default";
      driver = "dir";
    }];

    profiles = [{
      name = "default";
      devices = {
        root = { path = "/"; pool = "default"; type = "disk"; };
        eth0 = { name = "eth0"; network = "incusbr0"; type = "nic"; };
      };
    }];
  };
}
