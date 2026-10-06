# EternaTV — radio and video

A 24/7 internet radio station plus always-playing video channels, running on trigkey. Public at `radio.ericsharma.xyz` and `video.ericsharma.xyz`.

## Common tasks

| Task | Do |
|------|----|
| Play newly uploaded music now | `sudo systemctl restart radio-autodj` (otherwise it reloads every 600 s) |
| Add a video channel | Add an entry to `channels` in `radio-video.nix`, then `rebuild`. Suggestions are commented out above the list. |
| Update the orchestrator | Commit in `/home/eric/eternatv`, then `nix flake update eternatv` and `rebuild` |
| A channel plays filler | Raise `cacheTarget` |

## Never break these

1. **Never expose port 8089.** The orchestrator API has no auth. Public traffic reaches it only through the sidecar, which gates captures behind a session and allowlists everything else.
2. **Keep both 7-day prunes equal.** `radio-video-captures-prune` (bucket files) and `eternatv-captures-db-prune` (database rows) live in different modules. If they differ, "Your Captures" lists files that 404, or the bucket fills with unlisted files.
3. **The orchestrator requires `rclone-radio-video-captures`.** If it starts first, it writes under the empty mountpoint and rclone hides those files.
4. **nginx `/api/` keeps `proxy_read_timeout 300s`.** `/api/capture/stop` waits up to 300 s for ffmpeg. A shorter timeout returns 504 and leaves a file with no database row.
5. **The nginx `types { }` block lists every MIME type.** At server scope it replaces the inherited map entirely.

## Modules and ports

| Module | Runs |
|--------|------|
| `hosts/nixos/optional/radio.nix` | Icecast + Liquidsoap |
| `hosts/nixos/optional/radio-video.nix` | Orchestrator, HLS output, nginx |
| `hosts/nixos/optional/eternatv-sidecar.nix` | Hono auth sidecar + Postgres database `eternatv` |

The orchestrator and player come from the `eternatv` flake input, built from `/home/eric/eternatv`.

| Port (all on `127.0.0.1`) | What | Pangolin route |
|---------------------------|------|----------------|
| 8000 | Icecast, mount `/stream` | `radio.ericsharma.xyz` |
| 8088 | nginx: HLS, player page, `/api/` | `video.ericsharma.xyz` |
| 8089 | Orchestrator API, **no auth** | never |
| 8090 | Hono sidecar | — |

## Audio

- Liquidsoap shuffles `/var/lib/radio/music`, a read-only mount of the `radio` bucket, and sends 128 kbps MP3 to Icecast `/stream`.
- **Icecast passwords stay out of the Nix store**, which is world-readable. `radio.nix` gives the module placeholders, renders `/run/icecast/icecast.xml` (mode 0640) with `envsubst` from sops in `ExecStartPre`, and overrides `ExecStart` with `lib.mkForce`.
- The source password must be in **both** `radio/icecast-env` and `radio/liquidsoap-env`.

## Video

The orchestrator downloads public-domain film from the Library of Congress, normalizes it to MP4, and writes HLS per channel. Channels are always mid-programme, like broadcast TV.

| Channel | URL | Source |
|---------|-----|--------|
| `main` | `video.ericsharma.xyz/` | Every collection below, random with a seen-history. The only channel taking submissions. |
| `animation` | `video.ericsharma.xyz/#animation` | `collections/origins-of-american-animation` |
| `vintage-nyc` | `video.ericsharma.xyz/#vintage-nyc` | `collections/early-films-of-new-york-1898-to-1906` |

**The video has no audio track.** The browser plays a separate audio source beside it:

| Source | Default |
|--------|---------|
| `icecast`: trigkey radio | |
| `nts1`: NTS 1 | |
| `nts2`: NTS 2 | yes |

- Each source has a loopback URL for the orchestrator and a public URL for the browser.
- NTS points at `stream-relay-geo.ntslive.net`, never a radiomast edge hostname. Edge names rotate and break playback silently.
- The video unit starts `after` Icecast but doesn't require it.

| Tunable | Value | Effect |
|---------|-------|--------|
| `cacheTarget` | 3 | Ready MP4s per channel |
| `hlsListSize` | 60 | Segments kept (~4 s each, ~4 min of replay) |
| `captureMaxSeconds` | 240 | Longest capture |
| `captureRetention` | `7d` | How long a capture lives |

## Captures

- Captures live only in the `radio-video-captures` bucket, mounted read-write at `/var/lib/radio-video/captures`. The rclone cache (1 GB, 1 hour) is `/var/cache/rclone-radio-video-captures`.
- Capture audio comes from a tmpfs buffer, `/run/radio-video/audio-buf`: 130 × 2 s = 260 s, just over `captureMaxSeconds`.
- The bucket prune talks S3 directly, so it still works when the mount is down.

## Checks

```bash
curl -s http://127.0.0.1:8088/main/stream.m3u8
curl -s http://127.0.0.1:8089/channels | jq
curl -s http://127.0.0.1:8089/now | jq
mpv http://127.0.0.1:8000/stream

systemctl status rclone-radio-video-captures radio-video-orchestrator
systemctl status icecast radio-autodj eternatv-sidecar
```
