{
  config,
  lib,
  pkgs,
  ...
}:

let
  port = 8080;

  # Rendered into /var/lib/sabnzbd/sabnzbd.ini on every start. The @TOKEN@
  # placeholders are substituted from /run/secrets/* by `replace-secret`, so no
  # credential ever reaches the world-readable Nix store.
  #
  # __version__ must match CONFIG_VERSION in the sabnzbd package (19 for 4.5.x).
  # A lower number makes SABnzbd run its config migrations over a file that is
  # already current; a higher number makes it refuse to start.
  iniTemplate = pkgs.writeText "sabnzbd.ini.in" ''
    __version__ = 19

    [misc]
    host = 0.0.0.0
    port = ${toString port}
    api_key = @API_KEY@
    nzb_key = @NZB_KEY@

    # inet_exposure 0 = deny non-local addresses. RFC1918 clients count as
    # local, so the LAN reaches the UI and the public internet would not, even
    # if the firewall rule below were ever widened by accident.
    inet_exposure = 0
    # SABnzbd rejects any request whose Host header it does not recognise.
    host_whitelist = gmktec, gmktec.local, 192.168.0.51, localhost, 127.0.0.1

    download_dir = /data/usenet/incomplete
    complete_dir = /data/usenet/complete
    # Group-writable output, so a later Sonarr/Radarr in the `media` group can
    # hardlink the finished files into /data/media.
    permissions = 0775

    auto_browser = 0
    check_new_rel = 0
    # SABnzbd cannot update itself here — the package comes from the flake.
    disable_api_key = 0
    # Unpack while downloading. Saves a full second pass over large releases.
    direct_unpack = 1
    # Keep RAM use bounded on a box that also runs local inference.
    cache_limit = 1G

    [logging]

    [servers]
    [[news.frugalusenet.com]]
    name = news.frugalusenet.com
    displayname = Frugal (primary)
    host = news.frugalusenet.com
    port = 563
    ssl = 1
    ssl_verify = 3
    username = @FRUGAL_USER@
    password = @FRUGAL_PASS@
    connections = 45
    priority = 0
    enable = 1
    optional = 0
    [[bonus.frugalusenet.com]]
    name = bonus.frugalusenet.com
    displayname = Frugal (bonus block)
    host = bonus.frugalusenet.com
    port = 563
    ssl = 1
    ssl_verify = 3
    username = @FRUGAL_USER@
    password = @FRUGAL_PASS@
    connections = 20
    priority = 1
    enable = 1
    # `optional` is the "Backup server" checkbox in the web UI: query this
    # backbone only for articles the primary could not supply.
    optional = 1

    [categories]
    [[*]]
    name = *
    order = 0
    pp = 3
    script = None
    dir =
    priority = 0
    [[tv]]
    name = tv
    order = 1
    pp = 3
    script = None
    dir = tv
    priority = -100
    [[movies]]
    name = movies
    order = 2
    pp = 3
    script = None
    dir = movies
    priority = -100
    [[music]]
    name = music
    order = 3
    pp = 3
    script = None
    dir = music
    priority = -100
    [[prowlarr]]
    name = prowlarr
    order = 4
    pp = 3
    script = None
    dir = prowlarr
    priority = -100
  '';

  renderConfig = pkgs.writeShellScript "sabnzbd-render-config" ''
    set -euo pipefail
    umask 077
    install -m 0600 ${iniTemplate} /var/lib/sabnzbd/sabnzbd.ini

    # replace-secret does a literal substitution from a file. Never `source` a
    # secret and interpolate it: a password containing `$` would be expanded by
    # the shell into nothing.
    replace() {
      ${pkgs.replace-secret}/bin/replace-secret "$1" "$2" /var/lib/sabnzbd/sabnzbd.ini
    }
    replace '@API_KEY@' ${config.sops.secrets."sabnzbd/api-key".path}
    replace '@NZB_KEY@' ${config.sops.secrets."sabnzbd/nzb-key".path}
    replace '@FRUGAL_USER@' ${config.sops.secrets."sabnzbd/frugal-username".path}
    replace '@FRUGAL_PASS@' ${config.sops.secrets."sabnzbd/frugal-password".path}
  '';
in
{
  # ── SABnzbd (Usenet download and extraction engine) ──────────────────────────
  # Port: 8080 (LAN only, see the nftables rule below)
  # Config: /var/lib/sabnzbd/sabnzbd.ini — REGENERATED ON EVERY START from this
  #   module. Changes made in the web UI survive until the next restart and are
  #   then lost. Edit this file instead.
  # Data: /data/usenet/{incomplete,complete} (see ./media-storage.nix)
  # NOT backed up — the config is reproduced from this module plus sops, and
  # the downloads are re-fetchable.
  #
  # Two Frugal Usenet connections: news.frugalusenet.com as the primary
  # backbone, bonus.frugalusenet.com marked `optional` so it is queried only for
  # missing articles. Both use SSL on 563.

  # ── Secrets ──────────────────────────────────────────────────────────────────
  # Scalars rather than one env block: SABnzbd reads no environment variables,
  # so each value is substituted into the ini by path.
  sops.secrets =
    lib.genAttrs
      [
        "sabnzbd/api-key"
        "sabnzbd/nzb-key"
        "sabnzbd/frugal-username"
        "sabnzbd/frugal-password"
      ]
      (_: {
        owner = "sabnzbd";
        group = "sabnzbd";
        mode = "0400";
      });

  services.sabnzbd = {
    enable = true;
    # openFirewall would publish 8080 on every interface. The scoped nftables
    # rule below is narrower.
    openFirewall = false;
  };

  # `unrar` is in the package's PATH and is unfree; it is allowed in
  # ../common/default.nix. Without it SABnzbd cannot extract the RAR sets that
  # most Usenet posts use.

  # The upstream module already declares this user; add only the shared group
  # that lets its output be hardlinked out of /data later.
  users.users.sabnzbd.extraGroups = [ "media" ];

  systemd.services.sabnzbd = {
    after = [ "sops-nix.service" ];
    # /data is on the root filesystem, but be explicit: an empty download dir
    # would otherwise be silently created if that ever changes.
    unitConfig.RequiresMountsFor = "/data";
    serviceConfig = {
      ExecStartPre = renderConfig;
      # 0002 keeps the setgid `media` group writable on everything SABnzbd
      # creates, which is what lets the *arr apps hardlink later.
      UMask = "0002";
      Restart = "on-failure";
      RestartSec = "10s";

      # Hardening — same posture as the other small services on this host.
      # ProtectSystem = "strict" is deliberately NOT used: SABnzbd must write
      # to /data, and ReadWritePaths plus the state dir is the tighter statement
      # of the same intent.
      NoNewPrivileges = true;
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ReadWritePaths = [ "/data" ];
    };
  };

  # ── Firewall ─────────────────────────────────────────────────────────────────
  # LAN subnet only, never the public path. SABnzbd here runs with no username
  # or password — whoever reaches the port controls the downloader and can read
  # the Frugal account usage. Same reasoning as the llama-server rule in
  # ./default.nix.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport ${toString port} accept comment "sabnzbd web UI from LAN"
  '';
}
