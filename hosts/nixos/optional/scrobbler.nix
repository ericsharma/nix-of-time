{ ... }:

{
  # ── Multi-Scrobbler (music scrobbling) ───────────────────────────────────────
  # Data dir: /srv/multi-scrobbler/config
  # Port: 9078

  virtualisation.oci-containers.containers.multi-scrobbler = {
    image = "foxxmd/multi-scrobbler";
    ports = [ "127.0.0.1:9078:9078" ];
    volumes = [
      "/srv/multi-scrobbler/config:/config"
    ];
    environment = {
      TZ = "America/New_York";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/multi-scrobbler 0755 root root -"
    "d /srv/multi-scrobbler/config 0755 root root -"
  ];
}
