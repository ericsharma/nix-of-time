{ config, lib, ... }:

let
  # Not 0.0.0.0: dnsmasq (incusbr0 on trigkey) and aardvark-dns (podman bridges
  # on both hosts) already hold :53 on their bridge addresses, and a wildcard
  # bind collides with them. Both LAN addresses are DHCP reservations on the
  # router. Only trigkey is on the tailnet.
  bindHosts =
    {
      trigkey = [
        "127.0.0.1"
        "192.168.0.202"
        "100.73.1.39"
      ];
      gmktec = [
        "127.0.0.1"
        "192.168.0.51"
      ];
    }
    .${config.networking.hostName};
in
{
  # ── AdGuard Home (network-wide DNS ad blocker) ───────────────────────────────
  # Runs on trigkey (primary DNS) and gmktec (secondary DNS), with the same
  # settings. Each instance keeps its own query log and stats.
  # DNS: 53 on the LAN and loopback addresses, plus Tailscale on trigkey
  # Web UI: 127.0.0.1:3010, on the LAN as http://adguard.local (trigkey) and
  #   http://gmktec.adguard.local (gmktec), via inventory.nix
  # Data: /var/lib/AdGuardHome (query log + stats only, not backed up — the
  #   config that matters is below)
  #
  # The LAN gets it through the router's DHCP DNS setting. Tailnet devices get
  # it through the Tailscale admin console (DNS → nameserver 100.73.1.39).
  # See docs/services/adguardhome.md.
  #
  # The web UI has no login. It is LAN-only through portless, the same tier as
  # Ladder. Anyone on the LAN can pause blocking; nothing more.

  services.adguardhome = {
    enable = true;
    # Grafana holds 3000 on trigkey.
    host = "127.0.0.1";
    port = 3010;
    # Nix owns every key set below and rewrites it on each start. Keys set in
    # the UI (per-client settings, blocked services) survive restarts. Custom
    # rules do not: `user_rules` is set below, so add rules here, not in the UI.
    mutableSettings = true;
    settings = {
      dns = {
        bind_hosts = bindHosts;
        port = 53;
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "https://cloudflare-dns.com/dns-query"
        ];
        upstream_mode = "load_balance";
        # Resolves the DoH hostnames above. Plain IPs, so DNS never depends on
        # itself.
        bootstrap_dns = [
          "9.9.9.9"
          "1.1.1.1"
        ];
        # Reverse lookups for LAN addresses go to the router, which knows the
        # DHCP hostnames. This is what puts names instead of IPs in the query log.
        use_private_ptr_resolvers = true;
        local_ptr_upstreams = [ "192.168.0.1" ];
      };
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };
      # iCloud Private Relay sends Safari's lookups to Apple, past this
      # blocker. Apple's documented network opt-out is an NXDOMAIN for these
      # two names; devices then show "Private Relay is turned off for this
      # network". Away from home, Private Relay works as normal.
      # https://developer.apple.com/support/prepare-your-network-for-icloud-private-relay/
      user_rules = [
        "||mask.icloud.com^$dnsrewrite=NXDOMAIN"
        "||mask-h2.icloud.com^$dnsrewrite=NXDOMAIN"
      ];
      filters = [
        {
          enabled = true;
          id = 1;
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
        }
        {
          enabled = true;
          id = 2;
          name = "OISD big";
          url = "https://big.oisd.nl";
        }
        # Malware, phishing, and scam domains — the two lists above cover ads
        # and trackers only. Low breakage by design.
        {
          enabled = true;
          id = 3;
          name = "HaGeZi Threat Intelligence Feeds";
          url = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/tif.txt";
        }
      ];
    };
  };

  # 100.73.1.39 exists only once tailscaled is up. If AdGuard starts first the
  # bind fails and the unit restarts every 10 s (the module sets Restart=always)
  # until it succeeds.
  systemd.services.adguardhome = lib.mkIf config.services.tailscale.enable {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
  };

  # DNS for the LAN and the tailnet only. Not allowedUDPPorts, which would open
  # 53 on every interface, including the container bridges. The tailscale0
  # rules match nothing on a host without Tailscale.
  networking.firewall.extraInputRules = lib.mkAfter ''
    ip saddr 192.168.0.0/24 udp dport 53 accept comment "AdGuard DNS from LAN"
    ip saddr 192.168.0.0/24 tcp dport 53 accept comment "AdGuard DNS from LAN"
    iifname "tailscale0" udp dport 53 accept comment "AdGuard DNS from tailnet"
    iifname "tailscale0" tcp dport 53 accept comment "AdGuard DNS from tailnet"
  '';
}
