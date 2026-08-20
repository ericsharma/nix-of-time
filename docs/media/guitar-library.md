# The guitar library

The guitar library is a collection of instructional DVDs, ripped losslessly and
served by Jellyfin. It is the largest single body of media in the fleet:
roughly 47 GB across about 330 objects.

It is also the pipeline that touches the most parts of the system, and no
single module describes all of it. This page does.

## The chain

```
physical DVD in the USB optical drive on trigkey
        │  ddrescue
        ▼
   lossless ISO in /home/eric          ← the offline master, kept
        │  ffmpeg dvdvideo demuxer, -c copy
        ▼
   per-chapter .mkv files              ← MPEG-2 video + AC3 audio
        │  rclone copy, guitar-rw key
        ▼
   garage bucket `guitar`              ← one folder per course
        │  rclone mount, guitar-ro key, --read-only
        ▼
   /srv/jellyfin/media on trigkey
        │
        ▼
   Jellyfin at trigkey:8096
```

The `/dvd-rip` Claude Code skill runs steps one to three. See
[Claude Code skills](../claude-skills.md).

## Why lossless

A DVD holds MPEG-2 video and AC3 audio at a fixed bitrate. The disc *is* the
master. There is no higher-quality source to encode from, so a re-encode can
only lose data. Every step in the chain copies streams bit for bit:

- `ddrescue` makes a byte-exact image, retries unreadable sectors, and keeps a
  resumable mapfile. Plain `dd` does none of that, and optical drives often
  fail on the last few sectors.
- `ffmpeg -c copy` remuxes. It does not transcode.

Expect about 2× the disc size on local disk while the rip runs — the ISO plus
the extracted clips, near 9 GB for a DVD-5. Check `df -h /home/eric` first, and
delete the clips after the upload verifies. The ISO stays as the master.

## The folder convention

One folder per disc, in title case: `<Instructor> - <Course Title>`. For
example, `Chet Atkins Fingerstyle Workshop/`. Jellyfin shows each folder as one
item, so the folder name is the name a viewer reads. A clean course title
usually comes off the first page of the disc's booklet PDF.

## How Jellyfin sees it

`hosts/nixos/optional/jellyfin.nix` mounts the bucket read-only at
`/srv/jellyfin/media`. The mountpoint sits deliberately *outside* Jellyfin's
`StateDirectory`, so a Jellyfin state reset cannot touch it.

MKV files of MPEG-2 and AC3 direct-play on most clients. The rest get a light
transcode. Note that trigkey has no VAAPI setup, unlike gmktec — a transcode
here runs on the CPU.

After a rebuild, add the library in the Jellyfin setup wizard and point it at
`/srv/jellyfin/media`.

## Adding a disc to the existing bucket

Nothing to deploy. Rip, upload into a new folder, then start a scan in the
Jellyfin UI at **Dashboard → Scan All Libraries**.

The manual scan is not optional. Jellyfin's inotify watcher does not see
changes on a FUSE mount, and rclone caches the directory listing for
`--dir-cache-time` — about a minute. S3 has no change notification, so
`--poll-interval` does nothing here.

## Gotchas

These are all recorded because they cost real time.

- **A new `.nix` file must be `git add`ed before a rebuild.** The flake only
  sees tracked files. An untracked module is skipped in silence: the closure
  barely changes and the units never appear.
- **The mount is read-only on purpose.** You cannot rename or delete through
  `/srv/jellyfin/media`. Act on the bucket with the `-rw` key instead
  (`rclone moveto`, `rclone delete`).
- **A rename in the bucket is a server-side copy and delete.** Jellyfin treats
  the result as a new item, so watch state resets. Nothing is corrupted.
- **`ENV_AUTH=true` is mandatory** on any rclone S3 remote pointed at Garage.
  See [Garage object storage](garage.md).
- **Feed the ISO file to the `dvdvideo` demuxer, not a loop mount.** Reading the
  image directly avoids spurious `libdvdcss` and device-permission warnings.
- **Run a nix-store binary as root with `sudo "$(command -v <tool>)"`.** Plain
  `sudo <tool>` fails, because sudo's `secure_path` strips the nix store from
  `PATH`.

## The ascii prefix

The `guitar` bucket also holds an `ascii/` prefix. The `/media-to-ascii` skill
renders a clip as ASCII video with the `mediatoascii` CLI, re-attaches the
original audio, and uploads the result there. It is unrelated to the Jellyfin
library, and Jellyfin's library root is the bucket root, so keep an eye on
whether the prefix ever needs excluding.
