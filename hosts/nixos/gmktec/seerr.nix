{
  config,
  lib,
  pkgs,
  ...
}:

let
  port = 5055;
  # The upstream module picks this from system.stateVersion: 25.11 here, so the
  # pre-26.05 location. Read it back rather than hard-code it.
  settingsFile = "${config.services.seerr.configDir}/settings.json";

  # Quality profile that every request gets. The stock Sonarr/Radarr profiles
  # are all the stack has today, and the existing library uses this one.
  profileName = "HD-1080p";

  reconcile = pkgs.writeShellScript "seerr-reconcile" ''
    set -euo pipefail

    PATH=${
      lib.makeBinPath [
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ]
    }

    base="http://127.0.0.1:${toString port}/api/v1"

    for _ in $(seq 1 60); do
      curl -sf -o /dev/null "$base/status" && break
      sleep 2
    done
    curl -sf -o /dev/null "$base/status" || { echo "seerr did not answer within 120s" >&2; exit 1; }

    # Seerr writes its API key into settings.json on first start.
    key="$(jq -r '.main.apiKey' ${settingsFile})"

    # Same contract as api() in ./servarr-api.nix: body to stdout on 2xx, body
    # to the journal and a failure otherwise.
    api() {
      _method="$1"
      _path="$2"
      shift 2
      _body="$(mktemp)"
      _code="$(
        curl -s -o "$_body" -w '%{http_code}' -X "$_method" \
          -H "X-Api-Key: $key" \
          -H "Content-Type: application/json" \
          "$base$_path" "$@"
      )"
      if [ "$_code" -ge 200 ] && [ "$_code" -lt 300 ]; then
        cat "$_body"
        rm -f "$_body"
      else
        echo "$_method $_path -> HTTP $_code: $(cat "$_body")" >&2
        rm -f "$_body"
        return 1
      fi
    }

    # The API key acts as user 1, and user 1 only exists after a Jellyfin admin
    # has signed in through the setup wizard once. That sign-in is also what
    # links Jellyfin and mints Seerr's Jellyfin API key, and it needs the admin
    # password, which this repo does not hold. Until then there is nothing to
    # reconcile: say so and succeed, so a fresh deploy does not show a failed
    # unit.
    if ! api GET /settings/main >/dev/null 2>&1; then
      echo "seerr has no owner yet: sign in at http://seerr.local with a Jellyfin admin," >&2
      echo "then run: systemctl restart seerr-reconcile" >&2
      exit 0
    fi

    # Create or update one Sonarr/Radarr entry, keyed by name. The last argument
    # is merged in with --argjson, so it must be strict JSON (quoted keys), not
    # jq object syntax. Seerr validates the body against its OpenAPI schema, so
    # a field is either the right type or left out. /test both proves Seerr can
    # reach the app with this key and returns its profiles, so the profile ID is
    # looked up by name instead of hard-coded.
    upsert_arr() {
      _kind="$1"
      _name="$2"
      _port="$3"
      _apikey="$4"
      _dir="$5"
      _extra="$6"

      _conn="$(jq -n --arg k "$_apikey" --argjson p "$_port" \
        '{hostname: "127.0.0.1", port: $p, apiKey: $k, useSsl: false, baseUrl: ""}')"
      _test="$(api POST "/settings/$_kind/test" -d "$_conn")"
      _profile="$(jq -e --arg n "${profileName}" \
        '.profiles | map(select(.name == $n)) | .[0].id' <<<"$_test")" \
        || { echo "$_name has no quality profile named ${profileName}" >&2; return 1; }

      _payload="$(jq --arg name "$_name" --arg dir "$_dir" --argjson prof "$_profile" \
        --argjson extra "$_extra" '
          . + {
            name: $name,
            activeProfileId: $prof,
            activeProfileName: "${profileName}",
            activeDirectory: $dir,
            is4k: false,
            isDefault: true,
            tags: [],
            externalUrl: "",
            syncEnabled: true,
            preventSearch: false,
            tagRequests: false
          } + $extra' <<<"$_conn")"

      _id="$(api GET "/settings/$_kind" | jq -r --arg n "$_name" 'map(select(.name == $n)) | .[0].id // empty')"
      if [ -n "$_id" ]; then
        api PUT "/settings/$_kind/$_id" -d "$_payload" >/dev/null
        echo "updated $_kind/$_name (id $_id, profile $_profile)"
      else
        api POST "/settings/$_kind" -d "$_payload" >/dev/null
        echo "created $_kind/$_name (profile $_profile)"
      fi
    }

    # Request a film as soon as it is out on disc or streaming, not at the
    # cinema date, when only CAM copies exist.
    upsert_arr radarr Radarr 7878 "$RADARR__AUTH__APIKEY" /data/media/movies \
      '{"minimumAvailability": "released"}'

    # Sonarr v4 dropped language profiles, so /test returns none.
    # activeLanguageProfileId is left out: the schema allows it to be missing
    # but not null. Anime goes to the same folder and profile:
    # there is no separate anime library.
    upsert_arr sonarr Sonarr 8989 "$SONARR__AUTH__APIKEY" /data/media/tv \
      '{
        "activeAnimeProfileId": null,
        "activeAnimeLanguageProfileId": null,
        "activeAnimeDirectory": "",
        "animeTags": [],
        "seriesType": "standard",
        "animeSeriesType": "anime",
        "enableSeasonFolders": true,
        "monitorNewItems": "all"
      }'

    # Enable every Jellyfin film and series library, so Seerr marks a title as
    # available once Jellyfin has it. ?sync=true refreshes the list from
    # Jellyfin first.
    libs="$(api GET '/settings/jellyfin/library?sync=true' | jq -r 'map(.id) | join(",")')"
    api GET "/settings/jellyfin/library?enable=$libs" \
      | jq -r '"jellyfin libraries enabled: " + (map(select(.enabled) | .name) | join(", "))'

    # Seerr talks to Jellyfin on 127.0.0.1, but builds its "Play on Jellyfin"
    # links from externalHostname. Empty, those links send the browser to its
    # own loopback. Both routes merge a partial body into the stored settings.
    api POST /settings/jellyfin -d '{"externalHostname": "http://jellyfin.local"}' >/dev/null
    api POST /settings/main -d '{"applicationUrl": "http://seerr.local"}' >/dev/null
    echo "links point at http://jellyfin.local, app URL http://seerr.local"

    api POST /settings/initialize >/dev/null
  '';
in
{
  # ── Seerr (request front end for Jellyfin, Sonarr and Radarr) ────────────────
  # Port: 5055 (loopback; LAN reaches it as http://seerr.local through portless)
  # Config: the setup wizard once (Jellyfin admin sign-in), then this module.
  #   seerr-reconcile.service writes the Sonarr and Radarr links and the
  #   Jellyfin library selection through the REST API on every deploy.
  # Data: /var/lib/jellyseerr/config — settings.json and a SQLite database of
  #   users and requests.
  # NOT backed up — same call as the rest of the media stack. The links are
  #   rebuilt by the reconcile unit, users re-import from Jellyfin, and only the
  #   request history is lost.
  #
  # Seerr is the merged successor of Jellyseerr and Overseerr. A request goes to
  # Radarr or Sonarr, which search Prowlarr's indexers and hand the release to
  # SABnzbd. Once Jellyfin has the file, Seerr's library scan marks it available.

  services.seerr = {
    enable = true;
    inherit port;
    openFirewall = false;
  };

  systemd.services.seerr.environment.HOST = "127.0.0.1";

  # restartUnits: a changed Sonarr or Radarr key must be pushed into Seerr too.
  sops.secrets."sonarr/env".restartUnits = [ "seerr-reconcile.service" ];
  sops.secrets."radarr/env".restartUnits = [ "seerr-reconcile.service" ];

  systemd.services.seerr-reconcile = {
    description = "Reconcile Seerr links to Sonarr, Radarr and Jellyfin";
    after = [
      "seerr.service"
      "sonarr.service"
      "radarr.service"
      "jellyfin.service"
    ];
    requires = [ "seerr.service" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ reconcile ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = [
        config.sops.secrets."sonarr/env".path
        config.sops.secrets."radarr/env".path
      ];
      ExecStart = reconcile;
      # Runs as root only to read settings.json under the DynamicUser state
      # directory and the two API keys; it writes nothing on disk.
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };
}
