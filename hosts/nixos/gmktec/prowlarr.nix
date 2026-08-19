{
  config,
  pkgs,
  ...
}:

let
  port = 9696;
  apiUrl = "http://127.0.0.1:${toString port}/api/v1";

  # Prowlarr keeps indexers and download clients in its SQLite database, not in
  # config.xml, so no NixOS option can declare them. This oneshot reconciles
  # them through the REST API instead: it reads the current objects, and
  # creates or updates them to match what is written here. Running it twice
  # changes nothing, so a rebuilt machine converges to the same state.
  reconcile = pkgs.writeShellScript "prowlarr-reconcile" ''
    set -euo pipefail

    PATH=${
      pkgs.lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ]
    }

    key="$PROWLARR__AUTH__APIKEY"
    sab_key="$(cat ${config.sops.secrets."sabnzbd/api-key".path})"

    # On success the response body goes to stdout. On any non-2xx the body goes
    # to the journal instead and the call fails — Prowlarr explains a rejected
    # object in that body ("Invalid API Key", and so on), and a bare curl exit
    # code 22 would throw it away.
    api() {
      method="$1"
      path="$2"
      shift 2
      body="$(mktemp)"
      code="$(
        curl -s -o "$body" -w '%{http_code}' -X "$method" \
          -H "X-Api-Key: $key" \
          -H "Content-Type: application/json" \
          "${apiUrl}$path" "$@"
      )"
      if [ "$code" -ge 200 ] && [ "$code" -lt 300 ]; then
        cat "$body"
        rm -f "$body"
      else
        echo "$method $path -> HTTP $code: $(cat "$body")" >&2
        rm -f "$body"
        return 1
      fi
    }

    # Prowlarr migrates its database on first start, which can take a while on
    # a cold box. Wait rather than race it.
    ready=""
    for _ in $(seq 1 60); do
      if api GET /system/status >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 2
    done
    if [ -z "$ready" ]; then
      echo "prowlarr did not answer on ${apiUrl} within 120s" >&2
      exit 1
    fi

    # Create the object if no object of that name exists, otherwise update it in
    # place so the ID and any Sonarr/Radarr sync links survive.
    upsert() {
      endpoint="$1"
      name="$2"
      payload="$3"
      id="$(api GET "/$endpoint" | jq -r --arg n "$name" 'map(select(.name == $n)) | .[0].id // empty')"
      # Prowlarr tests the object before it saves it, and rejects one it cannot
      # reach or authenticate with. `?forceSave=true` does NOT bypass that here
      # (checked against 2.3.5), so a wrong or missing API key fails this unit
      # rather than saving a dead indexer. That is the wanted behaviour — the
      # journal names the reason.
      if [ -n "$id" ]; then
        api PUT "/$endpoint/$id" \
          -d "$(jq --argjson id "$id" '.id = $id' <<<"$payload")" >/dev/null
        echo "updated $endpoint/$name (id $id)"
      else
        api POST "/$endpoint" -d "$payload" >/dev/null
        echo "created $endpoint/$name"
      fi
    }

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
    sab="$(
      jq --arg k "$sab_key" '
        .name = "SABnzbd"
        | .enable = true
        | .priority = 1
        | .tags = []
        | .fields = (.fields | map(
            if .name == "host" then .value = "127.0.0.1"
            elif .name == "port" then .value = 8080
            elif .name == "useSsl" then .value = false
            elif .name == "urlBase" then .value = ""
            elif .name == "apiKey" then .value = $k
            elif .name == "category" then .value = "prowlarr"
            else . end))
      ' <<<"$sab"
    )"
    upsert downloadclient SABnzbd "$sab"
  '';
in
{
  # ── Prowlarr (indexer manager for the Usenet stack) ──────────────────────────
  # Port: 9696 (LAN only, see the nftables rule below)
  # Config: this module. config.xml comes from `settings` as PROWLARR__* env
  #   vars; the NZBGeek indexer and the SABnzbd download client are reconciled
  #   through the REST API by prowlarr-reconcile.service.
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
