# Media

Media is the largest workload in the fleet, and it is split across both
machines on purpose. Read this page first — it tells you which machine holds
what, and which of the more detailed pages you need.

## The split

| Machine | Media role | Storage |
|---------|-----------|---------|
| `trigkey` | Everything that is *curated* — ripped discs, photos, the radio and video streams | Garage S3 buckets on the internal SSD |
| `gmktec` | Everything that is *re-downloadable* — TV and film from Usenet | Plain ext4 at `/data` |

The rule behind the split is simple. If a loss of the file means you must rip
a disc again, it lives in Garage on trigkey and restic backs it up. If a loss
of the file means you download it again, it lives on gmktec and nothing backs
it up.

## The pipelines

Four independent pipelines put media into the fleet.

1. **Discs → Garage → Jellyfin.** A physical DVD becomes per-chapter MKV files
   in the `guitar` bucket. See [the guitar library](guitar-library.md).
2. **Usenet → `/data` → Jellyfin.** Prowlarr, SABnzbd, Sonarr and Radarr build
   a TV and film library on gmktec. See [the Usenet stack](../services/usenet.md).
3. **Garage → Icecast → the internet.** Liquidsoap makes a continuous audio
   stream, and an HLS video stream runs beside it. See [EternaTV](eternatv.md).
4. **A URL → Cobalt → Garage.** The Cobalt API downloads from YouTube,
   Instagram and similar sites into the `general-media` bucket. The `/cobalt-dl`
   Claude Code skill drives it. See [Claude Code skills](../claude-skills.md).

## The detail pages

| Page | What it covers |
|------|----------------|
| [Garage object storage](garage.md) | The S3 layer, every bucket, and the key convention |
| [The guitar library](guitar-library.md) | Disc to bucket to Jellyfin, end to end |
| [Jellyfin](jellyfin.md) | Why there are two Jellyfin servers, and which to use |
| [EternaTV](eternatv.md) | The radio stream, the video stream, and the capture feature |
| [Usenet stack](../services/usenet.md) | SABnzbd, Prowlarr, Sonarr, Radarr and the `/data` tree |

## Public media endpoints

| URL | Serves |
|-----|--------|
| `https://radio.ericsharma.xyz/stream` | The Icecast audio stream |
| `https://video.ericsharma.xyz` | The EternaTV player |


The `guitar` bucket also has Garage's website access switched on, so it can be
fronted at `guitar.ericsharma.xyz` through the website endpoint on
`127.0.0.1:3902`. Garage's website endpoint is used instead of presigned S3
URLs because it answers HTTP Range requests, which is what an HTML5 `<video>`
element needs to seek. Confirm the route in the Pangolin dashboard before you
rely on the name.

Both streams go through Newt to Pangolin. No port is open to the internet. See
[Networking and exposure](../networking.md).
