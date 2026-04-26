{ config, ... }:

# Cobalt — self-hosted media downloader (YouTube, Instagram, TikTok, X,
# SoundCloud, etc). Stateless tunnel API; pair with yt-session-generator so
# YouTube's BotGuard doesn't kneecap us.
#
# Pangolin dashboard setup required:
#   Resource → target: 10.0.100.10, port: 9000
#   Set headers:
#     X-Forwarded-Proto: https
#     X-Forwarded-Host:  cobalt.ericsharma.xyz
#   The API_URL env var below MUST match the public Pangolin URL — Cobalt
#   embeds it in tunnel responses, and clients fetch the bytes from there.
#
# Cobalt image is pinned (NOT :latest). The YouTube extractor depends on
# youtubei.js, which lags YouTube's player by weeks; an old pinned tag
# produces silent 0-byte tunnel responses on some videos. When that happens,
# bump the tag here. See https://github.com/imputnet/cobalt/releases
#
# Auth: keys.json is rendered from sops as a single scalar containing the
# full JSON ({ "<uuid>": { "name": "...", "limit": N } }). Cobalt requires
# clients to send `Authorization: Api-Key <uuid>` on every request.

let
  domain = "cobalt.ericsharma.xyz";
in
{
  virtualisation.oci-containers.containers = {

    # Sidecar: solves YouTube BotGuard challenges, returns poToken +
    # visitor_data. Internal-only — no port exposed to the LXC. If this
    # service becomes flaky, the dub-rip repo has a hardened Node version
    # at services/yt-token/ (jzstern/dub-rip); response format is identical.
    cobalt-token = {
      image = "ghcr.io/imputnet/yt-session-generator:webserver";
      extraOptions = [
        "--network=cobalt"
        "--network-alias=yt-session-generator"
        "--health-cmd=wget -qO- http://127.0.0.1:8080/ || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

    cobalt = {
      image   = "ghcr.io/imputnet/cobalt:11.7.1";
      ports   = [ "9000:9000" ];
      volumes = [
        "${config.sops.secrets."docker-services/cobalt/keys.json".path}:/keys.json:ro"
      ];
      environment = {
        API_URL                          = "https://${domain}/";
        API_PORT                         = "9000";
        API_KEY_URL                      = "file:///keys.json";
        API_AUTH_REQUIRED                = "1";
        YOUTUBE_SESSION_SERVER           = "http://yt-session-generator:8080/";
        YOUTUBE_SESSION_INNERTUBE_CLIENT = "WEB_EMBEDDED";
        DISABLE_TUNNELS                  = "0";
      };
      dependsOn    = [ "cobalt-token" ];
      extraOptions = [
        "--network=cobalt"
        "--health-cmd=wget -qO- http://127.0.0.1:9000/ || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=30s"
      ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-cobalt-token.preStart = ''
    docker network create cobalt 2>/dev/null || true
  '';

  # ── Wait for token sidecar healthy before starting Cobalt ─────────────────
  systemd.services.docker-cobalt.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' cobalt-token 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';
}
