# Media

Media is split across both machines by one rule. If losing a file means re-ripping a disc, it lives on trigkey and is backed up. If it means downloading again, it lives on gmktec and is not.

| Machine | Holds | Storage |
|---------|-------|---------|
| trigkey | Curated: ripped discs, photos, the radio and video streams | Garage S3 buckets |
| gmktec | Re-downloadable: the `/data` TV and film library | ext4 at `/data` |

## Pipelines

1. **Disc → Garage → Jellyfin.** A DVD becomes per-chapter MKVs in the `guitar` bucket. Run `/dvd-rip`. See [the guitar library](guitar-library.md).
2. **Garage → Icecast and HLS → the internet.** Liquidsoap streams audio, and an HLS video channel runs beside it. See [EternaTV](eternatv.md).
3. **URL → Cobalt → Garage.** Cobalt downloads from YouTube, Instagram, and similar sites into `general-media`. Run `/cobalt-dl`. See [Claude Code skills](../claude-skills.md).

## Pages

- [Garage object storage](garage.md): buckets, keys, rclone mounts
- [The guitar library](guitar-library.md): from disc to Jellyfin
- [Jellyfin](jellyfin.md): why there are two servers
- [EternaTV](eternatv.md): radio, video, captures

## Public endpoints

| URL | Serves |
|-----|--------|
| `https://radio.ericsharma.xyz/stream` | Icecast audio stream |
| `https://video.ericsharma.xyz` | EternaTV player |

Both go through Newt to Pangolin; no port is open. See [Networking](../networking.md).

The `guitar` bucket also has Garage website access on, so it can be served at `guitar.ericsharma.xyz` through `127.0.0.1:3902`. Confirm that route in the Pangolin dashboard before relying on it.
