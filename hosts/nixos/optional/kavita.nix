{ ... }:

{
  # ── Kavita (manga/comics/books reader) ───────────────────────────────────────
  # Data dirs: /srv/kavita/{manga,comics,books,config}
  # Port: 5000

  virtualisation.oci-containers.containers.kavita = {
    # v0.9.1.4 (Docker Hub has no 0.9.1.4 tag; 0.9.1 = latest = this digest)
    image = "jvmilazz0/kavita:0.9.1@sha256:31181a32f0dda73cae68721867028a7253d57881b58bea5754cd9e578e75421a";
    ports = [ "127.0.0.1:5000:5000" ];
    volumes = [
      "/srv/kavita/manga:/manga"
      "/srv/kavita/comics:/comics"
      "/srv/kavita/books:/books"
      "/srv/kavita/config:/kavita/config"
    ];
    environment = {
      TZ = "America/New_York";
    };
  };

  # Ensure data directories exist
  systemd.tmpfiles.rules = [
    "d /srv/kavita 0755 root root -"
    "d /srv/kavita/manga 0755 root root -"
    "d /srv/kavita/comics 0755 root root -"
    "d /srv/kavita/books 0755 root root -"
    "d /srv/kavita/config 0755 root root -"
  ];
}
