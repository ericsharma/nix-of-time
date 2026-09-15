{ ... }:

{
  # ── Ladder (http web proxy) ──────────────────────────────────────────────────
  # Fetches pages as Googlebot and applies a community ruleset that strips
  # paywall overlays. Self-hosted alternative to 12ft.io.
  # Port: 4210 (host) → 8080 (container)
  # Stateless — NOT backed up, nothing is written to disk.
  #
  # Loopback-only on purpose: an unauthenticated instance reachable from the
  # internet is an open proxy. To expose it via Pangolin, set USERPASS first
  # (see the sops block commented out below).

  virtualisation.oci-containers.containers.ladder = {
    image = "ghcr.io/everywall/ladder:v0.0.23";
    ports = [ "127.0.0.1:4210:8080" ];
    environment = {
      PORT = "8080";
      RULESET = "https://raw.githubusercontent.com/everywall/ladder-rules/main/ruleset.yaml";
      # Don't write every proxied URL to the journal.
      LOG_URLS = "false";
      EXPOSE_RULESET = "false";
    };
    # If exposing publicly, add basic auth:
    #   sops --set '["ladder"]["env"] "USERPASS=admin:<password>\n"' secrets/secrets.yaml
    # then uncomment both lines below.
    # environmentFiles = [ config.sops.secrets."ladder/env".path ];
  };

  # sops.secrets."ladder/env" = { };
}
