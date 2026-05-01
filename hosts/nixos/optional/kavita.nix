{ ... }:

{
  # ── Kavita (manga/comics/books reader) ───────────────────────────────────────
  # Data dirs: /srv/kavita/{manga,comics,books,config}
  # Port: 5000

  virtualisation.oci-containers.containers.kavita = {
    image = "jvmilazz0/kavita:latest";
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
