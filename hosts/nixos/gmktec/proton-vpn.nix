{ config, pkgs, ... }:

{
  # ── Proton VPN namespace (SABnzbd only) ──────────────────────────────────────
  # A network namespace named `proton` whose only way out is a WireGuard tunnel
  # to Proton VPN. Module: VPN-Confinement (flake input `vpn-confinement`).
  # A service joins it with
  #   systemd.services.<name>.vpnConfinement = { enable = true; vpnNamespace = "proton"; };
  # Only SABnzbd joins (./sabnzbd.nix). The *arrs, Jellyfin, Newt and the
  # restic server stay on the home connection.
  #
  # Kill switch: the namespace has no default route except the tunnel, and its
  # firewall drops every new connection on the veth to the host. When the tunnel
  # is down, SABnzbd cannot reach Frugal at all. DNS goes only to the DNS line
  # of the WireGuard config (Proton's 10.2.0.1).
  #
  # Addresses (module defaults):
  #   192.168.15.1  the namespace end of the veth (SABnzbd listens here)
  #   192.168.15.5  the host end (bridge `proton-br`)
  #
  # The WireGuard config comes from account.protonvpn.com → Downloads →
  # WireGuard configuration, one per device. It must keep its `DNS =` line,
  # or the namespace refuses to start. To change the server, generate a new
  # file and replace the sops value; restartUnits restarts the tunnel.
  #
  # The unit is `proton.service`. Check the tunnel with:
  #   sudo ip netns exec proton wg show
  #   sudo ip netns exec proton curl -s https://ipinfo.io/ip

  sops.secrets."proton/wg-gmktec" = {
    restartUnits = [ "proton.service" ];
  };

  vpnNamespaces.proton = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."proton/wg-gmktec".path;
  };

  systemd.services.proton.after = [ "sops-nix.service" ];

  # For `wg show` above. The module uses its own copy and puts none on PATH.
  environment.systemPackages = [ pkgs.wireguard-tools ];
}
