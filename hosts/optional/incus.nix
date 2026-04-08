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

  # Allow forwarded traffic to/from Incus containers
  networking.firewall.extraForwardRules = ''
    iifname "incusbr0" accept
    oifname "incusbr0" accept
  '';

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
  };

  # Apply the default profile only on first run — skips if instances already use it
  systemd.services.incus-default-profile = {
    after    = [ "incus.service" "incus-preseed.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.incus ];
    script = ''
      # Only apply if the default profile hasn't been configured yet
      if incus profile show default | grep -q "root:"; then
        echo "Default profile already configured, skipping"
        exit 0
      fi
      incus profile device add default root disk path=/ pool=default
      incus profile device add default eth0 nic name=eth0 network=incusbr0
    '';
  };
}
