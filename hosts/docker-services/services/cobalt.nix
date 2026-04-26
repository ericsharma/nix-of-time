{ config, pkgs, dub-rip, ... }:

# Cobalt — self-hosted media downloader (YouTube, Instagram, TikTok, X,
# SoundCloud, etc). Stateless tunnel API; pair with a YouTube PO token
# sidecar so YouTube's BotGuard doesn't kneecap us.
#
# Pangolin dashboard setup required:
#   Resource → target: 10.0.100.10, port: 9000
#   Set headers:
#     X-Forwarded-Proto: https
#     X-Forwarded-Host:  cobalt.blindjoe.xyz
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
#
# Token sidecar: built from jzstern/dub-rip (services/yt-token/). The
# upstream `imputnet/yt-session-generator:webserver` image was tried first
# and didn't work with Cobalt 11.7 (timeouts + missing /get_pot). The
# dub-rip Node service is what jzstern runs in prod against this same
# Cobalt version, and he ships fixes weekly. Pull updates with:
#   nix flake update dub-rip

let
  domain     = "cobalt.blindjoe.xyz";
  tokenImage = "cobalt-token-local:${dub-rip.shortRev or "dirty"}";
in
{
  virtualisation.oci-containers.containers = {

    # Sidecar: solves YouTube BotGuard, returns { potoken, visitor_data }.
    # Internal-only — no port exposed to the LXC. Image is built locally at
    # activation (see systemd preStart below) from the pinned dub-rip rev.
    cobalt-token = {
      image = tokenImage;
      extraOptions = [
        "--network=cobalt"
        "--network-alias=yt-session-generator"
        "--health-cmd=wget -qO- http://127.0.0.1:8080/health || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=5"
        "--health-start-period=60s"
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
        YOUTUBE_SESSION_SERVER           = "http://yt-session-generator:8080/token";
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

  # ── Build the token image from the pinned dub-rip source ──────────────────
  # Tag includes the source rev so `nix flake update dub-rip` produces a new
  # tag, which forces a rebuild here and a container restart in oci-containers.
  systemd.services.cobalt-token-build = {
    description = "Build cobalt-token Docker image from dub-rip source";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "docker-cobalt-token.service" ];
    after       = [ "docker.service" ];
    requires    = [ "docker.service" ];

    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if ! ${pkgs.docker}/bin/docker image inspect ${tokenImage} >/dev/null 2>&1; then
        ${pkgs.docker}/bin/docker build \
          -t ${tokenImage} \
          -f ${dub-rip}/Dockerfile.yt-token \
          ${dub-rip}
      fi
    '';
  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-cobalt-token = {
    after    = [ "cobalt-token-build.service" ];
    requires = [ "cobalt-token-build.service" ];
    preStart = ''
      docker network create cobalt 2>/dev/null || true
    '';
  };

  # ── Wait for token sidecar healthy before starting Cobalt ─────────────────
  systemd.services.docker-cobalt.preStart = ''
    until docker inspect --format '{{.State.Health.Status}}' cobalt-token 2>/dev/null | grep -q "healthy"; do
      sleep 2
    done
  '';
}
