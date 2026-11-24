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
    # Backup jobs write their last-success time here (trigkey/backup.nix).
    extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter-textfile" ];
  };

  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

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

  # LAN only: Prometheus on trigkey scrapes gmktec at its LAN address and
  # itself at 127.0.0.1 (loopback is always accepted). Not allowedTCPPorts,
  # which on trigkey also opened both ports on wg-pangolin and tailscale0.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport { 9100, 9101 } accept comment "node exporter and cadvisor from LAN"
  '';
}
