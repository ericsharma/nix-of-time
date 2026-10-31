{ ... }:

{
  # ── Syncthing (continuous file sync) ─────────────────────────────────────────
  # Web UI: loopback only. From another machine:
  #   ssh -L 8384:127.0.0.1:8384 eric@trigkey   then open http://localhost:8384
  # Vaults: /srv/obsidian/Work, /srv/obsidian/Brain 2.0
  # Sync protocol ports: 22000/tcp, 22000/udp
  # Discovery port: 21027/udp

  services.syncthing = {
    enable = true;
    user = "eric";
    group = "users";
    dataDir = "/srv/obsidian";
    configDir = "/home/eric/.config/syncthing";
    # Not openDefaultPorts, which opens the sync ports on every interface
    # (wg-pangolin included). The scoped rules below open the same ports.
    openDefaultPorts = false;
    # The UI runs as eric (passwordless sudo) and its config has no GUI user,
    # so it has no login. Loopback keeps it off the LAN, the tailnet, the LXC
    # bridge, and wg-pangolin.
    guiAddress = "127.0.0.1:8384";
    # Host check on: an SSH tunnel to localhost passes it, and it blocks DNS
    # rebinding from a browser on this host. Set false explicitly, because
    # syncthing-init only writes the keys it is given and the old `true`
    # would stay in config.xml.
    settings.gui.insecureSkipHostcheck = false;
  };

  # Sync from the LAN and from devices on the tailnet. Discovery is LAN
  # broadcast only.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport 22000 accept comment "syncthing sync from LAN"
    ip saddr 192.168.0.0/24 udp dport 22000 accept comment "syncthing sync (QUIC) from LAN"
    ip saddr 192.168.0.0/24 udp dport 21027 accept comment "syncthing discovery from LAN"
    iifname "tailscale0" tcp dport 22000 accept comment "syncthing sync from tailnet"
    iifname "tailscale0" udp dport 22000 accept comment "syncthing sync (QUIC) from tailnet"
  '';

  systemd.tmpfiles.rules = [
    "d /srv/obsidian          0755 eric users -"
    "d /srv/obsidian/Work     0755 eric users -"
    "d '/srv/obsidian/Brain 2.0' 0755 eric users -"
  ];
}
