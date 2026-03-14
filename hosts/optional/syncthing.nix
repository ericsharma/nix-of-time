{ ... }:

{
  # ── Syncthing (continuous file sync) ─────────────────────────────────────────
  # Web UI: http://trigkey:8384
  # Vaults: /srv/obsidian/Work, /srv/obsidian/Brain 2.0
  # Sync protocol ports: 22000/tcp, 22000/udp
  # Discovery port: 21027/udp

  services.syncthing = {
    enable   = true;
    user     = "eric";
    group    = "users";
    dataDir  = "/srv/obsidian";
    configDir = "/home/eric/.config/syncthing";
    openDefaultPorts = true;  # 22000/tcp+udp, 21027/udp
    guiAddress = "0.0.0.0:8384";
    settings.gui.insecureSkipHostcheck = true;
  };

  # Allow access to the web UI
  networking.firewall.allowedTCPPorts = [ 8384 ];

  systemd.tmpfiles.rules = [
    "d /srv/obsidian          0755 eric users -"
    "d /srv/obsidian/Work     0755 eric users -"
    "d '/srv/obsidian/Brain 2.0' 0755 eric users -"
  ];
}
