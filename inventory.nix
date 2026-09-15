# Single source of truth for facts about the homelab that more than one
# module needs to agree on. Pure data — no config, no logic. Pass via
# specialArgs.
#
# `address` — how *trigkey* reaches the host. Prometheus runs there, so this
#   is the scrape and probe address, which is why trigkey names itself
#   127.0.0.1 rather than its LAN address.
#
# `portlessAliases` — the `<name>.local` names that host publishes. Each entry
#   is `{ port; name; }`: the local TCP port behind the alias, and the human
#   name to show for it. Both consumers read this map:
#     * the host itself, via `services.portless.aliases` in its default.nix
#       (only `port` matters there — the alias key is the DNS name)
#     * monitoring.nix on trigkey, which turns every entry into a blackbox
#       probe so the Portless Services dashboard covers both machines. `name`
#       is what the dashboard labels the row with, so the table reads "SABnzbd"
#       rather than the slug `sabnzbd`.
#   The alias key stays a slug because it IS the mDNS name; `name` is free text
#   and is never resolved. Qualify `name` only when two hosts publish the same
#   service (see `finance` below) — otherwise the bare product name is clearer.
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
        "trigkey.finance" = {
          port = 5174;
          name = "Local Finance (trigkey)";
        };
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
        sonarr = {
          port = 8989;
          name = "Sonarr";
        };
        radarr = {
          port = 7878;
          name = "Radarr";
        };
        prowlarr = {
          port = 9696;
          name = "Prowlarr";
        };
        sabnzbd = {
          port = 8080;
          name = "SABnzbd";
        };
        jellyfin = {
          port = 8096;
          name = "Jellyfin";
        };
        # local-finance dev server, started by hand from ~/local-finance.
        finance = {
          port = 5174;
          name = "Local Finance";
        };
        # Document management and archiving (hosts/nixos/gmktec/papra.nix).
        papra = {
          port = 1221;
          name = "Papra";
        };
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
