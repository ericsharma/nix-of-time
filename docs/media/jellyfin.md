# Jellyfin

There are **two** Jellyfin servers in the fleet. They are unrelated, they hold
different libraries, and they share a port number but not a host. This page
exists because that arrangement looks like a mistake and is not one.

| | trigkey | gmktec |
|---|---------|--------|
| Module | `hosts/nixos/optional/jellyfin.nix` | `hosts/nixos/gmktec/jellyfin.nix` |
| Address | `http://trigkey:8096` | `http://192.168.0.51:8096`, or `http://jellyfin.local` |
| Library | The Garage `guitar` bucket, over a read-only rclone mount at `/srv/jellyfin/media` | `/data/media/{tv,movies}` on the internal NVMe |
| Content | Ripped instructional DVDs, MPEG-2 + AC3 | TV and film from Usenet, mostly x265 |
| Filled by | The `/dvd-rip` skill | Sonarr and Radarr |
| Transcoding | CPU only | VAAPI on the Vega iGPU of the 5825U |
| Accounts | Real accounts | Real accounts |
| Backed up | The bucket is, through the `garage` restic job. Jellyfin's own state is not. | No |

## Why two, and not one

The obvious alternative is a single Jellyfin on trigkey with `/data` exported
from gmktec over NFS. That was rejected for two reasons:

1. Every stream would cross the LAN twice — once from gmktec to trigkey, then
   once from trigkey to the client.
2. An NFS mount can hang, and a hung mount takes the media server down with it.

The libraries also have nothing in common. One is a small, curated, irreplaceable
set of rips. The other is a large, re-downloadable set that a `*arr` rewrites
continuously. Keeping them apart means a scan of one cannot disturb the other.

## Transcoding

Only gmktec has hardware acceleration. `hardware.graphics` is enabled there and
the `jellyfin` user is in the `video` and `render` groups. The switch itself is
a *setting in the Jellyfin dashboard*, not config — turn it on at
**Playback → Transcoding → VAAPI**, device `/dev/dri/renderD128`.

That is deliberate: most clients direct-play the x265 files already, so
acceleration only matters for the ones that cannot, such as an old TV or a
browser without HEVC. Without it those sessions compete with downloads and with
local LLM inference on the same box.

trigkey has no `hardware.graphics` block at all. Its transcodes run on the CPU.
That is acceptable because MPEG-2 is cheap to decode and most clients direct-play
it anyway.

## Exposure

Neither server is public. Both are LAN only.

- trigkey opens TCP 8096 with a plain firewall rule.
- gmktec opens 8096 with a scoped nftables rule that admits `192.168.0.0/24`
  only, and publishes the mDNS name `jellyfin.local` through
  [Portless](../networking.md#portless--lan-names).

`openFirewall` is false on both. The upstream option would also open the DLNA
ports, which nothing here uses.

If you ever publish one through Pangolin, name the route for the machine, not
for the app. Two servers behind one name is a support problem you do not want.

## The mDNS name collision

Portless publishes each alias as an mDNS record. If both hosts published
`jellyfin`, mDNS would resolve the conflict by adding a suffix
(`jellyfin-2.local`), and which host wins would change across reboots.

Only gmktec runs Portless today, so `jellyfin.local` is unambiguous. If you
ever enable Portless on trigkey, give the two distinct names —
`jellyfin-media` on gmktec and `jellyfin-guitar` on trigkey, or similar.

## State and backup

Neither Jellyfin's own state directory is backed up. Both hold metadata, user
accounts, and watch progress, and both rebuild by rescanning the library.

Watch progress and accounts are the only things genuinely lost by a reinstall.
That is judged acceptable, and it matches how the rest of the stack treats
re-derivable state. Revisit the decision if either becomes the household media
server.

See also: [the guitar library](guitar-library.md), [the Usenet
stack](../services/usenet.md), [Backup and restore](../services/backup.md).
