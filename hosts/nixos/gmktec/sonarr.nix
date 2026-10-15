{
  config,
  pkgs,
  ...
}:

let
  port = 8989;
  servarrApi = import ./servarr-api.nix { inherit pkgs; };

  reconcile = pkgs.writeShellScript "sonarr-reconcile" ''
    set -euo pipefail

    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ]
    }

    api_url="http://127.0.0.1:${toString port}/api/v3"
    key="$SONARR__AUTH__APIKEY"
    . ${servarrApi}

    wait_ready

    ensure_root_folder /data/media/tv

    sab="$(
      api GET /downloadclient/schema \
        | jq -e 'map(select(.implementation == "Sabnzbd")) | .[0] // empty'
    )" || { echo "no Sabnzbd entry in Sonarr's download client schema" >&2; exit 1; }
    # Category "tv" matches the [[tv]] category in sabnzbd.ini, so finished
    # episodes land in /data/usenet/complete/tv — same filesystem as the root
    # folder above, which is what lets Sonarr hardlink instead of copy.
    upsert downloadclient SABnzbd "$(sabnzbd_payload "$(cat ${
      config.sops.secrets."sabnzbd/api-key".path
    })" tv <<<"$sab")"
  '';
in
{
  # ── Sonarr (TV series management) ────────────────────────────────────────────
  # Port: 8989 (LAN only, see the nftables rule below)
  # Config: this module. config.xml comes from `settings` as SONARR__* env vars;
  #   the root folder and the SABnzbd download client are reconciled through the
  #   REST API by sonarr-reconcile.service.
  # Data: /var/lib/sonarr (SQLite), library at /data/media/tv
  # NOT backed up — the database holds only the series list and history, both
  # rebuilt from the library and the indexer. The library itself is
  # re-downloadable; see ./media-storage.nix.

  # restartUnits: a changed key must reach the running app and be pushed back
  # through the reconcile, or the stored objects keep the old value.
  sops.secrets."sonarr/env".restartUnits = [
    "sonarr.service"
    "sonarr-reconcile.service"
    # Prowlarr stores this key in its app link, so that must be rewritten too.
    "prowlarr-reconcile.service"
  ];

  services.sonarr = {
    enable = true;
    # openFirewall would publish 8989 on every interface. The scoped nftables
    # rule below is narrower.
    openFirewall = false;
    environmentFiles = [ config.sops.secrets."sonarr/env".path ];
    settings = {
      server = {
        inherit port;
        bindaddress = "*";
      };
      # Same posture as Prowlarr: RFC1918 clients — all the firewall admits —
      # skip the login entirely, so no account is ever created.
      auth = {
        method = "Forms";
        required = "DisabledForLocalAddresses";
      };
      update.mechanism = "external";
      log.analyticsEnabled = false;
    };
  };

  # The upstream module declares this user; add only the shared group that lets
  # Sonarr read SABnzbd's output and hardlink it into /data/media/tv.
  users.users.sonarr.extraGroups = [ "media" ];

  systemd.services.sonarr = {
    after = [ "sops-nix.service" ];
    unitConfig.RequiresMountsFor = "/data";
    serviceConfig = {
      # 0002 keeps the setgid `media` group writable on everything Sonarr
      # creates in the library.
      UMask = "0002";
      ReadWritePaths = [ "/data" ];
    };
  };

  systemd.services.sonarr-reconcile = {
    description = "Reconcile Sonarr root folder and download client";
    after = [
      "sonarr.service"
      "sabnzbd.service"
    ];
    requires = [ "sonarr.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ reconcile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = config.sops.secrets."sonarr/env".path;
      ExecStart = reconcile;
      # Runs as root only to read the SABnzbd API key; it touches nothing else.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };

  # LAN subnet only. Sonarr asks for no login from a local address, so whoever
  # reaches this port controls the library.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport ${toString port} accept comment "sonarr web UI from LAN"
  '';
}
