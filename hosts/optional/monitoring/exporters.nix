{ ... }:

{
  # ── Node Exporter (hardware + OS metrics) ────────────────────────────────
  services.prometheus.exporters.node = {
    enable            = true;
    port              = 9100;
    enabledCollectors = [ "systemd" "processes" ];
  };

  # ── cAdvisor (container metrics) ─────────────────────────────────────────
  # Auto-detects Docker or Podman on the host — works on both trigkey
  # (Podman) and docker-services (Docker inside LXC).
  services.cadvisor = {
    enable = true;
    port   = 9101;
  };

  networking.firewall.allowedTCPPorts = [ 9100 9101 ];
}
