{
  config,
  pkgs,
  ...
}:

let
  port = 9696;
  servarrApi = import ./servarr-api.nix { inherit pkgs; };

  # Prowlarr keeps indexers, download clients and app links in its SQLite
  # database, not in config.xml, so no NixOS option can declare them. This
  # oneshot reconciles them through the REST API instead: it reads the current
  # objects, and creates or updates them to match what is written here. Running
  # it twice changes nothing, so a rebuilt machine converges to the same state.
  reconcile = pkgs.writeShellScript "prowlarr-reconcile" ''
    set -euo pipefail

    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
        pkgs.gnused
      ]
    }

    api_url="http://127.0.0.1:${toString port}/api/v1"
    key="$PROWLARR__AUTH__APIKEY"
    sab_key="$(cat ${config.sops.secrets."sabnzbd/api-key".path})"
    . ${servarrApi}

    wait_ready

    # ── NZBGeek indexer ──────────────────────────────────────────────────────
    # Start from Prowlarr's own schema entry so every field the current version
    # expects is present, then fill in the API key. Match on `.name`: NZBGeek is
    # a Newznab site, so its `definitionName` is "Newznab", not "NZBgeek".
    # Spelled exactly as upstream spells it — lowercase "g".
    nzbgeek="$(
      api GET /indexer/schema \
        | jq -e 'map(select((.name // "") | ascii_downcase == "nzbgeek")) | .[0] // empty'
    )" || { echo "no NZBgeek entry in Prowlarr's indexer schema" >&2; exit 1; }
    nzbgeek="$(
      jq --arg k "$NZBGEEK_API_KEY" '
        .name = "NZBgeek"
        | .enable = true
        | .appProfileId = 1
        | .priority = 25
        | .tags = []
        | .fields = (.fields | map(if .name == "apiKey" then .value = $k else . end))
      ' <<<"$nzbgeek"
    )"
    upsert indexer NZBgeek "$nzbgeek"

    # ── SABnzbd download client ──────────────────────────────────────────────
    # Lets a manual search in Prowlarr push the .nzb straight into SABnzbd, and
    # gives Sonarr/Radarr something to inherit when they are added.
    sab="$(
      api GET /downloadclient/schema \
        | jq -e 'map(select(.implementation == "Sabnzbd")) | .[0] // empty'
    )" || { echo "no Sabnzbd entry in Prowlarr's download client schema" >&2; exit 1; }
    upsert downloadclient SABnzbd "$(sabnzbd_payload "$sab_key" prowlarr <<<"$sab")"

    # ── Sonarr and Radarr app links ──────────────────────────────────────────
    # This is what makes Prowlarr the central point: with syncLevel fullSync it
    # pushes every indexer it holds into both apps and keeps them in step, so an
    # indexer is only ever configured here. Each app's own API key comes from
    # its sops env file — the same value that app's module pins.
    add_app() {
      app="$1"
      app_url="http://127.0.0.1:$2"
      app_key_file="$3"
      app_key="$(sed -n 's/^[A-Z]*__AUTH__APIKEY=//p' "$app_key_file")"
      [ -n "$app_key" ] || { echo "no API key in $app_key_file" >&2; return 1; }

      # Prowlarr tests the link by calling the app, so the app must already be
      # listening. systemd's After= is not enough on its own — see wait_app.
      wait_app "$app_url" "$app_key"

      schema="$(
        api GET /applications/schema \
          | jq -e --arg i "$app" 'map(select(.implementation == $i)) | .[0] // empty'
      )" || { echo "no $app entry in Prowlarr's application schema" >&2; return 1; }

      upsert applications "$app" "$(
        jq --arg n "$app" --arg k "$app_key" --arg u "$app_url" '
          .name = $n
          | .syncLevel = "fullSync"
          | .tags = []
          | .fields = (.fields | map(
              if .name == "prowlarrUrl" then .value = "http://127.0.0.1:${toString port}"
              elif .name == "baseUrl" then .value = $u
              elif .name == "apiKey" then .value = $k
              else . end))
        ' <<<"$schema"
      )"
    }

    add_app Sonarr 8989 ${config.sops.secrets."sonarr/env".path}
    add_app Radarr 7878 ${config.sops.secrets."radarr/env".path}
  '';
in
{
  # ── Prowlarr (indexer manager for the Usenet stack) ──────────────────────────
  # Port: 9696 (LAN only, see the nftables rule below)
  # Config: this module. config.xml comes from `settings` as PROWLARR__* env
  #   vars; the NZBGeek indexer, the SABnzbd download client, and the Sonarr and
  #   Radarr app links are reconciled through the REST API by
  #   prowlarr-reconcile.service.
  # Data: /var/lib/prowlarr (SQLite)
  # NOT backed up — every object in the database is recreated from this module
  # plus sops on the next start.

  # PROWLARR__AUTH__APIKEY pins the API key so it does not change on a rebuild
  # and break Sonarr/Radarr later. NZBGEEK_API_KEY is read by the reconcile
  # script from the same file.
  sops.secrets."prowlarr/env" = { };

  services.prowlarr = {
    enable = true;
    # openFirewall would publish 9696 on every interface. The scoped nftables
    # rule below is narrower.
    openFirewall = false;
    environmentFiles = [ config.sops.secrets."prowlarr/env".path ];
    settings = {
      server = {
        inherit port;
        bindaddress = "*";
      };
      # DisabledForLocalAddresses lets RFC1918 clients — the whole of what the
      # firewall rule below admits — through without a login, which matches how
      # llama-server is treated on this host. No account is ever created,
      # because no request that reaches Prowlarr is non-local. `method` names
      # the scheme used for anything that IS non-local; "Forms" is Prowlarr's
      # own login page. Use "External" only behind a reverse proxy that supplies
      # the authenticated user itself — revisit both keys before putting this
      # behind Newt.
      auth = {
        method = "Forms";
        required = "DisabledForLocalAddresses";
      };
      update.mechanism = "external";
      log.analyticsEnabled = false;
    };
  };

  systemd.services.prowlarr-reconcile = {
    description = "Reconcile Prowlarr indexers and download clients";
    after = [
      "prowlarr.service"
      "sabnzbd.service"
      # The app links need Sonarr and Radarr answering, and their own reconcile
      # units to have run — Prowlarr tests an app before it saves the link.
      "sonarr-reconcile.service"
      "radarr-reconcile.service"
    ];
    requires = [ "prowlarr.service" ];
    wantedBy = [ "multi-user.target" ];
    # Re-run when the script or either API key changes.
    restartTriggers = [ reconcile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = config.sops.secrets."prowlarr/env".path;
      ExecStart = reconcile;
      # Runs as root only to read the two secret files; it touches nothing else.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };

  # ── Firewall ─────────────────────────────────────────────────────────────────
  # LAN subnet only. Prowlarr is configured with no login page, so whoever
  # reaches this port can read the NZBGeek key and reconfigure the stack.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport ${toString port} accept comment "prowlarr web UI from LAN"
  '';
}
