{ ... }:

{
  # ── Memos (lightweight note-taking) ──────────────────────────────────────────
  # Data dir: /srv/memos
  # Port: 5230

  virtualisation.oci-containers.containers.memos = {
    image = "neosmemo/memos:26.11.0";
    ports = [ "127.0.0.1:5230:5230" ];
    volumes = [
      "/srv/memos:/var/opt/memos"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /srv/memos 0755 root root -"
  ];
}
