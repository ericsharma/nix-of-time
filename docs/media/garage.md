# Garage object storage

Garage is the S3-compatible object store on trigkey. It holds all curated media, and several services mount a bucket instead of using local disk.

To give a service a bucket, run `/garage` in Claude Code. It creates the bucket and key, sets permissions, and adds the sops entry.

| Item | Value |
|------|-------|
| Module | `hosts/nixos/trigkey/garage.nix` |
| Package | `pkgs.garage_2`, pinned. Read the release notes before a major version change. |
| Layout | Single node, LMDB, `replication_factor = 1`. Raise it only when a second node exists. |

## Endpoints

| Endpoint | Address | Notes |
|----------|---------|-------|
| S3 API | `[::]:3900` | Open to the LAN. Region `garage`. |
| RPC | `[::]:3901` | For a future cluster. Public address `192.168.0.202:3901`. |
| Website | `127.0.0.1:3902` | Root domain `.ericsharma.xyz`. Supports HTTP Range, so a `<video>` element can seek. |
| Admin API | `127.0.0.1:3903` | Token in sops, `garage/admin-token` |
| WebUI | `127.0.0.1:3909` | `hosts/nixos/trigkey/garage-webui.nix` |

## Buckets

| Bucket | Holds | Used by |
|--------|-------|---------|
| `guitar` | Ripped DVDs, one folder per course; `ascii/` renders | Jellyfin on trigkey (read-only mount) |
| `radio` | Music for the stream | Liquidsoap (read-only mount) |
| `radio-video-captures` | EternaTV replay clips, pruned after 7 days | EternaTV orchestrator (read-write mount) |
| `general-media` | Cobalt downloads | `/cobalt-dl` |
| `concert-music` | Concert recordings | Nothing yet |
| `pirouesync` | Class audio | PiroueSync |

```bash
sudo garage bucket list
sudo garage bucket info guitar
```

## Keys

- Each bucket gets its own keys, named for their permission: `<bucket>-ro` or `<bucket>-rw`.
- Anything that only reads gets `-ro`. That's why you can't rename or delete through `/srv/jellyfin/media`. Use the `-rw` key against the bucket.
- Credentials go in sops as an env block, because every consumer is an rclone unit with an `EnvironmentFile`:

```yaml
<service>:
  rclone-env: |
    AWS_ACCESS_KEY_ID=GK...
    AWS_SECRET_ACCESS_KEY=...
```

```bash
sudo garage key list
sudo garage key info guitar-ro --show-secret
```

## Mounting a bucket with rclone

Copy an existing unit exactly: `rclone-jellyfin`, `rclone-radio`, or `rclone-radio-video-captures`.

```
RCLONE_CONFIG_<NAME>_TYPE=s3
RCLONE_CONFIG_<NAME>_PROVIDER=Other
RCLONE_CONFIG_<NAME>_ENDPOINT=http://127.0.0.1:3900
RCLONE_CONFIG_<NAME>_REGION=garage
RCLONE_CONFIG_<NAME>_FORCE_PATH_STYLE=true
RCLONE_CONFIG_<NAME>_ENV_AUTH=true
```

Four things break mounts:

1. **`ENV_AUTH=true` is required.** Without it rclone ignores the key, tries anonymous access, and Garage returns `AccessDenied`.
2. **`--allow-other` needs the setuid wrapper.** Set `path = [ "/run/wrappers" ]` on the unit and `programs.fuse.userAllowOther = true`. The store's `fusermount` fails with `EPERM` otherwise.
3. **The unit must `require` `garage.service`.** Otherwise the mount starts empty, and anything written before rclone mounts is hidden underneath.
4. **Use `Type = "notify"`** so systemd waits until the mount is ready.

## Backup

The `garage` restic job (03:00) backs up `/var/lib/garage/data` and a `garage meta snapshot`, not the live LMDB file, which is inconsistent while open. The job fails loudly if the snapshot is missing.

Never add a job that walks a FUSE mountpoint. It backs up the same bytes over S3, much slower. See [Backup and restore](../services/backup.md).
