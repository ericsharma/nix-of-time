{
  config,
  lib,
  pkgs,
  ...
}:

{
  # ── Incus (containers + VMs) ──────────────────────────────────────────────
  virtualisation.incus.enable = true;

  # Incus requires nftables (not iptables)
  networking.nftables.enable = true;

  # KVM support for VMs (kvm-amd already loaded in hardware-configuration.nix)
  virtualisation.libvirtd.enable = true;

  users.users.eric.extraGroups = [ "incus-admin" ];

  # The LXC gets DHCP and DNS from Incus's dnsmasq on the bridge, and nothing
  # else on this host. Not trustedInterfaces: that let the LXC, which runs
  # internet-facing containers, reach every port on trigkey (Postgres,
  # garage-webui, Syncthing). trigkey's own connections into the LXC (Newt,
  # Prometheus, rebuild-docker) are outbound and need no rule.
  networking.firewall.interfaces.incusbr0 = {
    allowedUDPPorts = [
      53
      67
    ];
    allowedTCPPorts = [ 53 ];
  };

  # New connections from the LXC go to the internet only. With NAT it would
  # otherwise reach every LAN device as trigkey (gmktec admits the LAN to
  # SABnzbd, which has no login). Own table, not extraForwardRules: those
  # are ignored while networking.firewall.filterForward is off (the default),
  # and turning that on would also filter Podman and Tailscale forwarding.
  # A drop in any base chain is final, so the other tables cannot undo it.
  networking.nftables.tables.incus-isolation = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter; policy accept;
        iifname "incusbr0" ct state established,related accept
        iifname "incusbr0" ip daddr { 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16 } drop comment "LXC must not reach private nets"
      }
    '';
  };

  # ── Preseed: storage, networking, default profile ─────────────────────────
  virtualisation.incus.preseed = {
    networks = [
      {
        name = "incusbr0";
        type = "bridge";
        config = {
          "ipv4.address" = "10.0.100.1/24";
          "ipv4.nat" = "true";
          "ipv6.address" = "none";
        };
      }
    ];

    storage_pools = [
      {
        name = "default";
        driver = "dir";
      }
    ];
  };

  # Apply the default profile only on first run — skips if instances already use it
  systemd.services.incus-default-profile = {
    after = [
      "incus.service"
      "incus-preseed.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
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
