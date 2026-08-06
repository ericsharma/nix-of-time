{ ... }:

{
  # ── Node Exporter (hardware + OS metrics) ────────────────────────────────
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd"
      "processes"
    ];
  };

  # ── cAdvisor (container metrics) ─────────────────────────────────────────
  # Auto-detects Docker or Podman on the host — works on both trigkey
  # (Podman) and docker-services (Docker inside LXC).
  services.cadvisor = {
    enable = true;
    port = 9101;
    # The NixOS default is 127.0.0.1, which only works when Prometheus scrapes
    # the host as 127.0.0.1 (trigkey). A host reached by LAN address needs a
    # wildcard bind, matching node_exporter's default and the firewall rule below.
    listenAddress = "0.0.0.0";
  };

  networking.firewall.allowedTCPPorts = [
    9100
    9101
  ];
}
