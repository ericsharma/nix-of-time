{ pkgs, ... }:

{
  # ── FlareSolverr (Cloudflare challenge solver) ───────────────────────────────
  # A proxy that runs a real headless Chrome, solves the Cloudflare/DDoS-Guard
  # interstitial, and hands back the resulting cookies and HTML. Ladder calls it
  # for sites it cannot fetch on its own.
  # Port: 8191 (host) → 8191 (container)
  # Stateless — NOT backed up, nothing is written to disk.
  #
  # LAN name `flaresolverr.local` via the portless alias in inventory.nix. It has
  # no UI; the root path returns a JSON "FlareSolverr is ready!", which is what
  # the blackbox probe and a browser both see.

  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2";
    ports = [ "127.0.0.1:8191:8191" ];
    environment = {
      LOG_LEVEL = "info";
      # Dumping solved pages into the journal is a lot of noise and echoes the
      # content of whatever was fetched. Off unless something is being debugged.
      LOG_HTML = "false";
      TZ = "America/New_York";
    };
    extraOptions = [
      "--network=ladder"
      # Chrome writes its renderer scratch to /dev/shm. Podman's 64M default is
      # enough to crash a tab mid-solve on a heavy page, which surfaces as an
      # opaque timeout rather than an OOM.
      "--shm-size=1g"
    ];
  };

  # ── Shared container network ─────────────────────────────────────────────────
  # Ladder reaches FlareSolverr as `http://flaresolverr:8191`, which needs both
  # containers on the same user-defined podman network — the default bridge has
  # no DNS between containers. Declared here rather than in ladder.nix because
  # FlareSolverr is the reason it exists; ladder.nix joins it.
  #
  # `podman network create` is not idempotent, hence the `exists` guard.
  #
  # The interface name and subnet are both pinned. Left to itself podman names
  # the bridge by creation order (podman0, podman1, ...), which is not a name
  # the firewall rule below can rely on — it would silently move the day a
  # network is added or recreated in a different order.
  systemd.services.podman-network-ladder = {
    description = "Podman network shared by ladder and flaresolverr";
    wantedBy = [ "multi-user.target" ];
    before = [
      "podman-ladder.service"
      "podman-flaresolverr.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists ladder \
        || ${pkgs.podman}/bin/podman network create \
             --interface-name podman-ladder \
             --subnet 10.89.1.0/24 \
             ladder
    '';
  };

  # Container name resolution on a user-defined podman network is served by
  # aardvark-dns, listening on the bridge gateway (10.89.1.1:53). The host
  # firewall is `policy drop` and trusts only `lo` and `incusbr0`, so without
  # this rule every in-container lookup times out — `ladder` resolves nothing,
  # FLARESOLVERR_HOST never connects, and the failure looks like FlareSolverr
  # being down rather than a firewall drop.
  #
  # Scoped to DNS on this one interface rather than adding the bridge to
  # `trustedInterfaces`: containers here have no business reaching the host's
  # other ports.
  networking.firewall.extraInputRules = ''
    iifname "podman-ladder" udp dport 53 accept comment "aardvark-dns for the ladder podman network"
    iifname "podman-ladder" tcp dport 53 accept comment "aardvark-dns for the ladder podman network"
  '';

  systemd.services.podman-flaresolverr = {
    after = [ "podman-network-ladder.service" ];
    requires = [ "podman-network-ladder.service" ];
  };
}
