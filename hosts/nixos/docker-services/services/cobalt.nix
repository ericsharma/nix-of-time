{
  config,
  ...
}:

# Cobalt — self-hosted media downloader (YouTube, Instagram, TikTok, X,
# SoundCloud, etc). Stateless tunnel API.
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
# YouTube PoT sidecar: DISABLED again 2026-05-09.
#
# History:
#   2026-05-08: first disabled. Sidecar (jzstern/dub-rip's old yt-token)
#               ran youtube-po-token-generator in-process; jsdom OOM'd and
#               killed the container. ~90% CPU 24/7 in a restart loop.
#   2026-05-09: re-enabled after jzstern rewrote yt-token to isolate token
#               generation in a child process with its own heap cap.
#               Disabled again the same day — see below.
#
# Why disabled (round 2):
#   The worker-isolation rewrite fixes the *symptom* (no more OOM; parent
#   sat at 63MB rss / 13MB heap, totally healthy) but not the *cause*. The
#   underlying npm dep `youtube-po-token-generator ^0.6.0` (last release
#   2025-08-28) is stale relative to YouTube's current player JS — it now
#   hangs instead of crashing. Observed 22 generation attempts, 0 successes;
#   every attempt times out at 30s. /get_pot returns 503 forever, Cobalt
#   falls back to no-PoT mode, BotGuard'd long YouTube videos return empty
#   tunnels (file with ID3 metadata, 0 bytes audio).
#
#   Net: running the sidecar burns ~50% of one core to produce nothing the
#   user can see — the no-PoT fallback is identical to having no sidecar.
#
#   Don't be fooled by /health returning 200 — that's liveness only in the
#   new architecture. /ready (or /status.cached) is the real signal.
#
# Re-enable when EITHER:
#   - jzstern/dub-rip swaps to bgutils-js (or another maintained PoT lib), OR
#   - youtube-po-token-generator gets a real update that handles current
#     YouTube player JS.
#
# Issue tracking: filed against jzstern/dub-rip (see flake input). Check
# `services/yt-token/package.json` for the dep change before re-enabling.

let
  domain = "cobalt.blindjoe.xyz";
in
{
  virtualisation.oci-containers.containers = {

    cobalt = {
      image = "ghcr.io/imputnet/cobalt:11.7.1";
      ports = [ "9000:9000" ];
      volumes = [
        "${config.sops.secrets."docker-services/cobalt/keys.json".path}:/keys.json:ro"
      ];
      environment = {
        API_URL = "https://${domain}/";
        API_PORT = "9000";
        API_KEY_URL = "file:///keys.json";
        API_AUTH_REQUIRED = "1";
        DISABLE_TUNNELS = "0";
      };
      extraOptions = [
        "--network=cobalt"
        "--health-cmd=wget -qO- http://127.0.0.1:9000/ || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=3"
        "--health-start-period=30s"
      ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-cobalt.preStart = ''
    docker network create cobalt 2>/dev/null || true
  '';
}
