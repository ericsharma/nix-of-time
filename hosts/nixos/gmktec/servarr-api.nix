# Shell helpers shared by the reconcile units of the servarr apps on this host
# (Prowlarr, Sonarr, Radarr). Not a NixOS module — import it as a function:
#
#   servarrApi = import ./servarr-api.nix { inherit pkgs; };
#
# then source the result in a script that has already set:
#
#   api_url   e.g. http://127.0.0.1:8989/api/v3
#   key       that app's API key
#
# Sonarr, Radarr and Prowlarr all speak the same REST dialect: a `/schema`
# endpoint that returns a fully populated template object, and a collection
# endpoint that takes it back with the fields filled in. Everything below is
# built on that, so one set of helpers serves all three.
#
# Every local inside these functions carries a `_` prefix. Bash has no function
# scope by default, so a plain `path` here would silently overwrite the caller's
# `path` — which is exactly what made ensure_root_folder once report that it had
# added a root folder called "/rootfolder".
{ pkgs }:

pkgs.writeText "servarr-api.sh" ''
  # On success the response body goes to stdout. On any non-2xx the body goes to
  # the journal instead and the call fails — these apps explain a rejected
  # object in that body ("Invalid API Key", "cannot connect to Sonarr", and so
  # on), and a bare curl exit code would throw it away.
  api() {
    _method="$1"
    _path="$2"
    shift 2
    _body="$(mktemp)"
    _code="$(
      curl -s -o "$_body" -w '%{http_code}' -X "$_method" \
        -H "X-Api-Key: $key" \
        -H "Content-Type: application/json" \
        "$api_url$_path" "$@"
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

  # These apps migrate their database on first start, which takes a while on a
  # cold box. Wait rather than race it.
  wait_ready() {
    for _ in $(seq 1 60); do
      if api GET /system/status >/dev/null 2>&1; then
        return 0
      fi
      sleep 2
    done
    echo "$api_url did not answer within 120s" >&2
    return 1
  }

  # As wait_ready, but for a DIFFERENT app than the one this script manages.
  # systemd's After= orders unit *starts*, and it only applies when both units
  # are in the same transaction — so a reconcile unit can still reach a
  # neighbour whose port is not open yet. Poll instead of trusting the ordering.
  wait_app() {
    _url="$1"
    _key="$2"
    for _ in $(seq 1 60); do
      if curl -sf -o /dev/null -H "X-Api-Key: $_key" "$_url/api/v3/system/status"; then
        return 0
      fi
      sleep 2
    done
    echo "$_url did not answer within 120s" >&2
    return 1
  }

  # Create the object if no object of that name exists, otherwise update it in
  # place so its ID — and anything else pointing at that ID — survives.
  #
  # These apps test an object before they save it and reject one they cannot
  # reach or authenticate with. `?forceSave=true` does not bypass that (checked
  # against Prowlarr 2.3.5), so a wrong key or an unwritable path fails the
  # unit rather than saving something dead. The journal names the reason.
  upsert() {
    _endpoint="$1"
    _name="$2"
    _payload="$3"
    _id="$(api GET "/$_endpoint" | jq -r --arg n "$_name" 'map(select(.name == $n)) | .[0].id // empty')"
    if [ -n "$_id" ]; then
      api PUT "/$_endpoint/$_id" -d "$(jq --argjson id "$_id" '.id = $id' <<<"$_payload")" >/dev/null
      echo "updated $_endpoint/$_name (id $_id)"
    else
      api POST "/$_endpoint" -d "$_payload" >/dev/null
      echo "created $_endpoint/$_name"
    fi
  }

  # Root folders have no name, only a path, so `upsert` does not fit them.
  # There is also nothing to update: a root folder IS its path.
  ensure_root_folder() {
    _folder="$1"
    if api GET /rootfolder | jq -e --arg p "$_folder" 'any(.[]; .path == $p)' >/dev/null; then
      echo "root folder $_folder already present"
    else
      api POST /rootfolder -d "$(jq -n --arg p "$_folder" '{path: $p}')" >/dev/null
      echo "added root folder $_folder"
    fi
  }

  # Fill in the SABnzbd connection on a download-client schema object. The
  # category field is named differently per app (tvCategory, movieCategory,
  # plain category), so match it by shape rather than by an exact name.
  sabnzbd_payload() {
    _sab_key="$1"
    _category="$2"
    jq --arg k "$_sab_key" --arg c "$_category" '
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
          elif (.name | ascii_downcase | endswith("category")) then .value = $c
          else . end))
    '
  }
''
