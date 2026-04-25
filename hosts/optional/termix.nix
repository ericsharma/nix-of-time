{ ... }:

{
  # ── Termix (browser-based terminal) ─────────────────────────────────────────
  # Port: 8080
  # Data dirs: /srv/termix/data

  virtualisation.oci-containers.containers.termix = {
    image = "ghcr.io/lukegus/termix:release-2.0.0";
    ports = [ "127.0.0.1:8080:8080" ];
    volumes = [
      "/srv/termix/data:/app/data"
    ];
    environment = {
      PORT = "8080";
    };
  };

  # Ensure data directories exist
  systemd.tmpfiles.rules = [
    "d /srv/termix 0755 root root -"
    "d /srv/termix/data 0755 root root -"
  ];
}
