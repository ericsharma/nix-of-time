# EternaTV — radio and video

EternaTV is a continuous internet radio station and a continuous video channel
that plays beside it. It is three NixOS modules, an external flake, a Postgres
database and a Garage bucket, and nothing else in the repo documented it.

| Module | What it stands up |
|--------|-------------------|
| `hosts/nixos/optional/radio.nix` | Icecast and Liquidsoap — the audio stream |
| `hosts/nixos/optional/radio-video.nix` | The orchestrator, the HLS output, and nginx |
| `hosts/nixos/optional/eternatv-sidecar.nix` | The Hono auth sidecar and its database |

The orchestrator and the player come from the `eternatv` flake input, built
from a separate repository at `/home/eric/eternatv`.

## Ports

| Port | Bound to | What |
|------|----------|------|
| 8000 | `127.0.0.1` | Icecast, mount `/stream` |
| 8088 | `127.0.0.1` | nginx — HLS, the player page, and `/api/` | 
| 8089 | `127.0.0.1` | The orchestrator API. **No authentication at all.** |
| 8090 | `127.0.0.1` | The Hono sidecar |

Public routes in Pangolin: `radio.ericsharma.xyz` to 8000, and
`video.ericsharma.xyz` to 8088.

Never expose 8089. The orchestrator does no authentication, and it is reachable
publicly only through the sidecar, which gates the capture routes behind a
session and forwards an explicit allowlist of everything else.

## The audio side

Liquidsoap reads a playlist from `/var/lib/radio/music`, which is a read-only
rclone FUSE mount of the Garage `radio` bucket. It shuffles, and it reloads the
playlist every 600 seconds. Output is 128 kbps MP3 to the Icecast mount
`/stream`.

To pick up a new upload at once instead of waiting for the reload:

```bash
sudo systemctl restart radio-autodj
```

### The Icecast password problem

The upstream NixOS Icecast module writes `icecast.xml` into the nix store, and
**everything in the nix store is world-readable**. Putting the source and admin
passwords in the module options would publish them.

The workaround is in `radio.nix` and is worth understanding before you edit it:

1. The module's options hold shell-style *placeholders*, not real passwords.
2. `environment.etc."icecast.xml.template"` gives that placeholder config a
   stable path.
3. An `ExecStartPre` runs `envsubst` over the template into
   `/run/icecast/icecast.xml`, at mode 0640, using the sops env file.
4. `ExecStart` is overridden with `lib.mkForce` to read the rendered file.

The source password must appear in **both** `radio/icecast-env` (Icecast
validates it) and `radio/liquidsoap-env` (Liquidsoap sends it).

## The video side

The orchestrator downloads public-domain film from the Library of Congress,
normalises each item to MP4, and keeps an ffmpeg process writing HLS segments
per channel. The result is a channel that is always mid-programme, like a
broadcast station — not a playlist you start.

### Channels

Channels are declared in the `channels` list at the top of `radio-video.nix`.
Each one gets its own HLS manifest and walks its collections in a fixed order,
then loops.

| Channel | Source |
|---------|--------|
| `main` | Auto-derived: the union of every collection below |
| `animation` | `collections/origins-of-american-animation` |
| `vintage-nyc` | `collections/early-films-of-new-york-1898-to-1906` |

`main` is special twice over. It picks at random with a seen-history, so a large
pool does not repeat too eagerly, and it is the only channel that accepts user
submissions.

The player reads the channel from the URL fragment:

- `https://video.ericsharma.xyz/` — `main`
- `https://video.ericsharma.xyz/#animation`

To add a channel, add an entry to `channels` and rebuild. Commented-out
suggestions for other Library of Congress collections sit right above the list.

### Audio is not in the video stream

The HLS master carries **no audio**. The browser plays a separate audio stream
of the viewer's choice next to the silent video.

| Source | Kind | Default |
|--------|------|---------|
| `icecast` — trigkey radio | Icecast status JSON | |
| `nts1` — NTS 1 | NTS live API | |
| `nts2` — NTS 2 | NTS live API | yes |

Each source carries two URLs. The orchestrator runs on this host, so it uses a
loopback URL; the player runs in a browser, so it needs a public one.

The NTS entries point at the stable geo relay
(`stream-relay-geo.ntslive.net`), never at a radiomast edge node. Edge
hostnames rotate, and an expired one breaks the player and the audio taps in
silence.

Because audio is separate, a brief Icecast outage is no longer a reason for the
video to refuse to start. The unit keeps `after = icecast.service` for ordering
but does not require it.

### Tunables

| Setting | Value | Effect |
|---------|-------|--------|
| `cacheTarget` | 3 | Normalised MP4s kept ready per channel. Higher survives a slow download; lower uses less disk. |
| `hlsListSize` | 60 | Segments kept on disk. At about 4 s each, that is roughly 4 minutes of instant-replay lookback. |
| `captureMaxSeconds` | 240 | Longest capture a user may take |
| `captureRetention` | `7d` | How long a capture survives |

If a channel falls back to filler, raise `cacheTarget` first.

## Captures

A viewer can capture what just played. Captures do **not** live on the SSD.
`/var/lib/radio-video/captures` is a read-write FUSE mountpoint for the Garage
bucket `radio-video-captures`, so the bucket is the only place a capture
persists. rclone keeps a bounded local cache — 1 GB, 1 hour — under
`/var/cache/rclone-radio-video-captures`, which evicts itself.

The audio for a capture comes from a rolling per-source buffer in
`/run/radio-video/audio-buf`. That is tmpfs, so it never touches disk and it
disappears on restart. It holds 130 segments of 2 s, which is 260 s — just over
`captureMaxSeconds`.

### Retention runs in two places, and both matter

| Timer | Deletes | Where |
|-------|---------|-------|
| `radio-video-captures-prune` | Capture MP4s older than 7 days | The Garage bucket, over S3 |
| `eternatv-captures-db-prune` | Capture rows older than 7 days | The `eternatv` Postgres database |

These two **must** keep the same 7-day figure. The MP4 prune and the row prune
are in different modules, so it is easy to change one and not the other. If the
rows outlive the files, "Your Captures" fills with entries that 404 on
playback. If the files outlive the rows, the bucket grows and nothing lists the
objects.

The bucket prune talks to Garage over S3 directly, not through the FUSE mount.
That way it still works when the mount unit is down, and cache eviction stays
fully separate from retention.

## Ordering that is not optional

- `radio-video-orchestrator` **requires** `rclone-radio-video-captures`. If the
  orchestrator started first it would write captures into the empty directory
  underneath the mountpoint, and rclone would then shadow them.
- The nginx `/api/` proxy sets `proxy_read_timeout 300s`. `/api/capture/stop`
  blocks while ffmpeg muxes, and the orchestrator allows up to 300 s for that.
  A shorter timeout returns 504 to the user while the capture finishes upstream,
  which orphans the file with no database row.
- The nginx server block declares a full `types { ... }` map. A `types` block at
  server scope **replaces** the inherited http-level map completely, so every
  MIME type the player touches has to be re-declared — not just the HLS ones.

## Checks

```bash
curl -s http://127.0.0.1:8088/main/stream.m3u8
curl -s http://127.0.0.1:8089/channels | jq
curl -s http://127.0.0.1:8089/now | jq
mpv http://127.0.0.1:8000/stream

systemctl status rclone-radio-video-captures radio-video-orchestrator
systemctl status icecast radio-autodj eternatv-sidecar
```

## To change the orchestrator

Edit `/home/eric/eternatv`, commit, then in this repo:

```bash
nix flake update eternatv
sudo nixos-rebuild switch --flake .#trigkey
```
