# The guitar library

Instructional DVDs, ripped losslessly into the Garage `guitar` bucket and served by Jellyfin on trigkey. About 47 GB across ~330 objects.

## Add a disc

1. Check free space: `df -h /home/eric`. A DVD-5 needs about 9 GB while ripping (ISO plus clips).
2. Put the disc in trigkey's USB drive and run `/dvd-rip` in Claude Code.
3. Name the folder `<Instructor> - <Course Title>`. The booklet PDF usually has the clean title. Jellyfin shows this name.
4. In Jellyfin (`http://trigkey:8096`), run **Dashboard → Scan All Libraries**. This is required: Jellyfin can't see changes on the FUSE mount, and rclone caches listings for about a minute.

No deploy needed.

## The chain

```
DVD at /dev/sr0
  │  ddrescue                    byte-exact, retries bad sectors, resumable
  ▼
ISO in /home/eric                the master, kept
  │  ffmpeg dvdvideo, -c copy
  ▼
per-chapter .mkv                 MPEG-2 + AC3, no re-encode
  │  rclone copy, guitar-rw key
  ▼
bucket `guitar`                  one folder per course
  │  rclone mount, guitar-ro key, --read-only
  ▼
/srv/jellyfin/media → Jellyfin :8096
```

Every step copies streams bit for bit, because the disc is the master and any re-encode only loses data. Delete the local MKVs after the upload verifies; keep the ISO.

## Gotchas

- **The mount is read-only.** Rename or delete in the bucket with the `-rw` key (`rclone moveto`, `rclone delete`). A rename makes Jellyfin treat the file as new, resetting watch state.
- **`ENV_AUTH=true`** is required on every rclone remote. See [Garage](garage.md).
- **Feed the ISO file to `dvdvideo`**, not a loop mount. It avoids `libdvdcss` and device-permission warnings.
- **Nix binaries under sudo:** use `sudo "$(command -v ddrescue)"`. Plain `sudo ddrescue` fails because `secure_path` drops the store from `PATH`.
- **Transcoding is CPU only.** trigkey has no VAAPI. Most clients direct-play MPEG-2 anyway.

## Notes

- The mountpoint sits outside Jellyfin's `StateDirectory`, so a state reset can't touch the library. After a fresh install, add the library at `/srv/jellyfin/media` in the setup wizard.
- The `ascii/` prefix holds `/media-to-ascii` renders. Jellyfin's library root is the bucket root, so the prefix may need excluding one day.
