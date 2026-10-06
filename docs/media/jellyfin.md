# Jellyfin

There are two separate Jellyfin servers, one per machine, with different libraries. That is on purpose.

| | trigkey | gmktec |
|---|---------|--------|
| Use for | Guitar DVDs | TV and films |
| Address | `http://trigkey:8096` | `http://jellyfin.local` or `http://192.168.0.51:8096` |
| Module | `hosts/nixos/optional/jellyfin.nix` | `hosts/nixos/gmktec/jellyfin.nix` |
| Library | `guitar` bucket, read-only rclone mount at `/srv/jellyfin/media` | `/data/media/{tv,movies}` on the NVMe |
| Filled by | `/dvd-rip` | Sonarr, Radarr |
| Transcoding | CPU | VAAPI on the Vega iGPU |
| Backed up | The bucket is (`garage` job); Jellyfin state is not | No |

## Turn on VAAPI (gmktec)

It's a dashboard setting, not Nix config: **Playback → Transcoding → VAAPI**, device `/dev/dri/renderD128`. The Nix side (`hardware.graphics`, `video` and `render` groups) is already done.

Most clients direct-play the x265 files. VAAPI matters for the ones that can't, like an old TV or a browser without HEVC.

## Why two servers

- One server reading `/data` over NFS would send every stream across the LAN twice.
- A hung NFS mount would take the media server down.
- The libraries share nothing: small and irreplaceable versus large and constantly rewritten. Separate servers mean one scan can't disturb the other.

## Exposure

Both are LAN only. trigkey opens 8096 with a plain rule; gmktec admits `192.168.0.0/24` only. `openFirewall` is off on both, because it would also open the DLNA ports.

If you ever add a Pangolin route, name it after the machine, not "jellyfin".

## The mDNS name collision

Both hosts run Portless, and only gmktec may publish `jellyfin`. If trigkey published it too, mDNS would rename one to `jellyfin-2.local`, and which host wins would change across reboots. If trigkey needs a name, use a distinct one such as `jellyfin-guitar`.

## State

Neither server's state directory is backed up. A rescan rebuilds metadata; accounts and watch progress would be lost. Revisit this if either becomes the household media server.
