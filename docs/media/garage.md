# Garage object storage

[Garage](https://garagehq.deuxfleurs.fr/) is the S3-compatible object store on
trigkey. It holds every piece of curated media in the fleet, and several
services mount a bucket instead of keeping files on the local disk.

Module: `hosts/nixos/trigkey/garage.nix`. Package: `pkgs.garage_2`, pinned on
purpose — read the release notes before you change the major version.

## Endpoints

| Endpoint | Address | Notes |
|----------|---------|-------|
| S3 API | `[::]:3900` | Open to the LAN by an explicit firewall rule. Region is `garage`. |
| RPC | `[::]:3901` | For a future cluster. Public address `192.168.0.202:3901`. |
| Website | `127.0.0.1:3902` | Root domain `.ericsharma.xyz`, index `index.html` |
| Admin API | `127.0.0.1:3903` | Token in sops at `garage/admin-token` |
| Garage WebUI | `127.0.0.1:3909` | Browser dashboard, `hosts/nixos/trigkey/garage-webui.nix` |

The node runs with `replication_factor = 1` and the LMDB engine. It is a
single node. Raise the replication factor only when a second node exists.

### Why the website endpoint exists

A browser that plays a video must seek, and seeking needs HTTP Range support.
Presigned S3 URLs do not give that cleanly, so buckets that feed a `<video>`
element use the website endpoint on port 3902 instead. Pangolin fronts one
subdomain per bucket.

## Buckets

| Bucket | Purpose | Consumer |
|--------|---------|----------|
| `guitar` | Ripped instructional DVDs, one folder per course. Also holds the `ascii/` prefix from the `/media-to-ascii` skill. | Jellyfin on trigkey, read-only rclone mount |
| `radio` | Audio files for the Icecast stream | Liquidsoap, read-only rclone mount |
| `radio-video-captures` | User "instant replay" clips from EternaTV. Pruned after 7 days. | EternaTV orchestrator, read-write rclone mount |
| `general-media` | Downloads made through the Cobalt API | The `/cobalt-dl` skill |
| `concert-music` | Concert recordings | Not yet wired to a service |
| `pirouesync` | Class audio for PiroueSync | PiroueSync |

`guitar` is by far the largest, and it is the one that justifies the backup
job. Check the current numbers at any time:

```bash
sudo garage bucket list
sudo garage bucket info guitar
```

## The key convention

Every bucket gets its own access key, and the key name states its permission:

- `<bucket>-ro` — read only. Give this to anything that only plays or serves.
- `<bucket>-rw` — read and write. Give this to anything that uploads.

A service that only reads must never hold a `-rw` key. Jellyfin, for example,
gets `guitar-ro`, which is why you cannot rename or delete a file through
`/srv/jellyfin/media`. Do that against the bucket with the `-rw` key.

```bash
sudo garage key list
sudo garage key info guitar-ro --show-secret
```

Credentials go into `secrets/secrets.yaml` as an env block, because every
consumer is an rclone unit that reads an `EnvironmentFile`:

```yaml
<service>:
  rclone-env: |
    AWS_ACCESS_KEY_ID=GK...
    AWS_SECRET_ACCESS_KEY=...
```

See [Secrets](../secrets.md). The `/garage` Claude Code skill automates the
whole provisioning sequence — bucket, key, policy, and the sops entry.

## The rclone mount pattern

Three units mount a bucket as a FUSE filesystem: `rclone-jellyfin`,
`rclone-radio`, and `rclone-radio-video-captures`. They all follow the same
shape. If you add a fourth, copy it exactly.

```
RCLONE_CONFIG_<NAME>_TYPE=s3
RCLONE_CONFIG_<NAME>_PROVIDER=Other
RCLONE_CONFIG_<NAME>_ENDPOINT=http://127.0.0.1:3900
RCLONE_CONFIG_<NAME>_REGION=garage
RCLONE_CONFIG_<NAME>_FORCE_PATH_STYLE=true
RCLONE_CONFIG_<NAME>_ENV_AUTH=true
```

Three details cause almost every failure:

- **`ENV_AUTH=true` is mandatory.** Without it rclone ignores
  `AWS_ACCESS_KEY_ID` and tries anonymous access, and Garage refuses it with
  `AccessDenied`.
- **`--allow-other` needs the setuid wrapper.** Set `path = [ "/run/wrappers" ]`
  on the unit and set `programs.fuse.userAllowOther = true`. The in-store
  `fusermount` exits with `EPERM` when a non-root user calls it.
- **The unit must `require` `garage.service`.** A mount that starts first
  shows an empty directory, and anything that writes into the mountpoint
  before rclone mounts on top of it is shadowed or lost.

Use `Type = "notify"` so systemd waits for the mount to be ready.

## Backup

The `garage` restic job in `hosts/nixos/trigkey/backup.nix` covers
`/var/lib/garage/data` and `/var/lib/garage/meta`.

The live LMDB metadata file is excluded. A copy of an open LMDB database is not
consistent, so the job calls `garage meta snapshot` first and backs up the
snapshot instead. The job checks that the snapshot really appeared and fails
loudly if it did not, because a silent failure here would only show up on the
day you need the restore.

Bucket data is therefore covered by the `garage` job alone. Do not add a second
job that walks a FUSE mountpoint — it would back up the same bytes over S3 and
be far slower.

See [Backup and restore](../services/backup.md).
