{ ... }:

{
  # ── Ladder (http web proxy) ──────────────────────────────────────────────────
  # Fetches pages as Googlebot and applies a community ruleset that strips
  # paywall overlays. Self-hosted alternative to 12ft.io.
  # Port: 4210 (host) → 8080 (container)
  # Stateless — NOT backed up, nothing is written to disk.
  #
  # The container binds 127.0.0.1 only. LAN reach comes from the portless
  # alias `ladder.local` (inventory.nix, trigkey.portlessAliases), which is the
  # same arrangement the *arrs and SABnzbd already have.
  #
  # Do NOT put this behind Pangolin without setting USERPASS first — an
  # unauthenticated instance reachable from the internet is an open proxy that
  # strangers will find and use, and the traffic leaves from this IP.

  virtualisation.oci-containers.containers.ladder = {
    image = "ghcr.io/everywall/ladder:v0.0.23";
    ports = [ "127.0.0.1:4210:8080" ];
    environment = {
      PORT = "8080";
      RULESET = "https://raw.githubusercontent.com/everywall/ladder-rules/main/ruleset.yaml";
      # Don't write every proxied URL to the journal.
      LOG_URLS = "false";
      EXPOSE_RULESET = "false";
      # Sites behind a Cloudflare interstitial. Resolved by container DNS on the
      # shared `ladder` network — the default upstream value is localhost, which
      # inside this container is the container itself. See ./flaresolverr.nix.
      FLARESOLVERR_HOST = "http://flaresolverr:8191";
    };
    extraOptions = [ "--network=ladder" ];
    # If exposing publicly, add basic auth:
    #   sops --set '["ladder"]["env"] "USERPASS=admin:<password>\n"' secrets/secrets.yaml
    # then uncomment both lines below.
    # environmentFiles = [ config.sops.secrets."ladder/env".path ];
  };

  # The network is created in ./flaresolverr.nix.
  systemd.services.podman-ladder = {
    after = [ "podman-network-ladder.service" ];
    requires = [ "podman-network-ladder.service" ];
  };

  # sops.secrets."ladder/env" = { };
}
