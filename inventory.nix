# Single source of truth for facts about the homelab that more than one
# module needs to agree on. Pure data — no config, no logic. Pass via
# specialArgs.
#
# `address` — how *trigkey* reaches the host. Prometheus runs there, so this
#   is the scrape and probe address, which is why trigkey names itself
#   127.0.0.1 rather than its LAN address.
#
# `portlessAliases` — the `<name>.local` names that host publishes, mapped to
#   the local port behind each. Both consumers read this map:
#     * the host itself, via `services.portless.aliases` in its default.nix
#     * monitoring.nix on trigkey, which turns every entry into a blackbox
#       probe so the Portless Services dashboard covers both machines.
#   A name may be published from ONE host only — mDNS suffixes a duplicate
#   (`finance-2.local`) and which host wins is unpredictable across reboots.
#   Convention: the host you develop on owns the bare name, the other prefixes
#   its own host name. See docs/networking.md.
{
  hosts = {
    trigkey = {
      address = "127.0.0.1";
      portlessAliases = {
        # local-finance also runs here on :5174; gmktec owns bare `finance`.
        "trigkey.finance" = 5174;
      };
    };
    docker-services = {
      address = "10.0.100.10";
      # The LXC has no portless instance — it is reached through trigkey.
      portlessAliases = { };
    };
    gmktec = {
      address = "192.168.0.51";
      portlessAliases = {
        sonarr = 8989;
        radarr = 7878;
        prowlarr = 9696;
        sabnzbd = 8080;
        jellyfin = 8096;
        # local-finance dev server, started by hand from ~/local-finance.
        finance = 5174;
      };
    };
  };

  # The port the portless daemon really listens on. `services.portless.
  # internalPort` defaults to the same value; nftables redirects 80 to it on
  # each host. Probes name it explicitly because the port-80 redirect is
  # installed in prerouting only, so it does not apply to a request a host
  # makes to itself.
  portlessPort = 1355;
}
