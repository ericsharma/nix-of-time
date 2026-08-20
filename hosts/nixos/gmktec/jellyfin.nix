{ config, pkgs, ... }:

{
  # ── Jellyfin (media server for the /data library) ────────────────────────────
  # Port: 8096 (LAN only, see the nftables rule below)
  # Config: this module + the first-run setup wizard (see below)
  # Data: /var/lib/jellyfin — metadata, users, watch state
  # NOT backed up. The library itself is re-downloadable, and the database is
  # rebuilt by rescanning. Watch progress and user accounts are the only things
  # genuinely lost by a reinstall; that is judged acceptable here, in line with
  # the rest of the stack. Revisit if this becomes the household media server.
  #
  # This is the SECOND Jellyfin in the fleet. The one on trigkey
  # (hosts/nixos/optional/jellyfin.nix) serves the Garage `guitar` bucket over
  # an rclone mount and is unrelated. They share a port number but not a host,
  # so nothing collides. The alternative — one Jellyfin on trigkey with /data
  # exported over NFS — was rejected: it would push every stream across the LAN
  # twice and add a mount that can hang.

  services.jellyfin = {
    enable = true;
    # openFirewall would also open the DLNA ports. The scoped rule below is
    # narrower and matches how the rest of this host is exposed.
    openFirewall = false;
    group = "media";
  };

  # VAAPI transcoding on the 5825U's Vega iGPU. Most clients direct-play the
  # x265 files already in the library, so this matters only for the ones that
  # cannot — an old TV, a browser without HEVC. Without it, those sessions fall
  # back to CPU transcoding and compete with downloads and local inference.
  #
  # The drivers and the device access are declared here; the switch itself is a
  # setting in Jellyfin's own dashboard, which is state rather than config.
  # Playback → Transcoding → VAAPI, device /dev/dri/renderD128.
  hardware.graphics = {
    enable = true;
    extraPackages = [
      pkgs.libva-vdpau-driver
      pkgs.libvdpau-va-gl
    ];
  };

  users.users.jellyfin.extraGroups = [
    "video"
    "render"
  ];

  systemd.services.jellyfin = {
    unitConfig.RequiresMountsFor = "/data";
    serviceConfig = {
      # Jellyfin only ever reads the library. Saying so here means a bug in it
      # cannot delete an episode, and makes the intent explicit for the next
      # service that touches /data.
      ReadOnlyPaths = [ "/data/media" ];
    };
  };

  # LAN subnet only, like every other web UI on this host. Jellyfin does have
  # real accounts, unlike SABnzbd and the *arrs, but its library is not
  # something to publish by accident.
  #
  # UDP 7359 is Jellyfin's auto-discovery responder. The server has
  # AutoDiscovery on by default, but with only the TCP rule here a client on
  # the WiFi broadcast and got no answer, so it never learned that the server
  # it reaches through Pangolin is also sitting on the same subnet. Every
  # stream then took the long way round: gmktec -> home upload -> the Pangolin
  # VPS in another city -> home download -> laptop. Opening this lets a local
  # client find 192.168.0.51:8096 and keep the traffic on the LAN.
  #
  # Pair it with Published server URIs in Dashboard -> Networking
  # (192.168.0.0/24=http://192.168.0.51:8096), which is Jellyfin state and not
  # set from here. Note that rule only matches clients that already connected
  # locally — a request arriving through the Newt tunnel carries the tunnel
  # peer as its source, not a 192.168.0.x address.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport 8096 accept comment "jellyfin from LAN"
    ip saddr 192.168.0.0/24 udp dport 7359 accept comment "jellyfin auto-discovery from LAN"
  '';
}
