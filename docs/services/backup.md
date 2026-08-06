# Backup and restore

trigkey holds every service and all the data. gmktec holds the only copy of
that data which survives the loss of trigkey.

| Item | Value |
|------|-------|
| Tool | [restic](https://restic.net/) |
| Source | trigkey |
| Target | gmktec, `restic-rest-server` on port 8000 |
| Storage | Samsung T7 external SSD, ext4, mounted at `/mnt/backup` |
| Repository | `/mnt/backup/restic/trigkey` |
| Config | `hosts/nixos/trigkey/backup.nix`, `hosts/nixos/gmktec/backup-server.nix` |

The repository is encrypted. gmktec cannot read the contents; it only stores
blocks. Port 8000 accepts connections from trigkey's address only.

## What is backed up

Five jobs write into one repository. `restic forget` groups snapshots by host
and paths, so each job's snapshots are retained independently.

| Job | Time | Contents |
|-----|------|----------|
| `databases` | 01:30 | Logical dumps: trigkey Postgres (`pg_dumpall`) plus the four Postgres containers in the LXC |
| `immich` | 02:00 | `/mnt/immich-data/immich` — 104 GB of photos and video |
| `garage` | 03:00 | `/var/lib/garage/data` plus a consistent metadata snapshot |
| `docker-services` | 04:00 | `/srv/docker-services` — rybbit, dawarich, karakeep, koito, endurain |
| `system-state` | 04:30 | Home Assistant, Grafana, Hermes, Prometheus TSDB, and the `/srv` service directories |

Retention is `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`. Only
`system-state` carries `pruneOpts`, so the repository is pruned once per night
instead of five times. That job also runs `restic check --read-data-subset=2%`,
which verifies the whole repository over roughly 50 days.

### Deliberately excluded

| Path | Reason |
|------|--------|
| `/var/lib/private/ollama` | 13 GB of model weights; re-downloadable |
| `/var/lib/containers` | Podman image cache; rebuilt from pinned tags |
| `/var/lib/incus` | LXC rootfs; declarative, and its data is bind-mounted |
| `/srv/jellyfin`, `/var/lib/radio*/…` | rclone views of Garage buckets, already covered by the `garage` job |

The rclone mounts are skipped by `--one-file-system`, not by an exclude list.

### Consistency

Databases are dumped, not copied. A copied live Postgres directory is not
guaranteed to restore.

Two things are file-level only:

- **ClickHouse** (rybbit analytics, ~11 GB). Backed up as files inside
  `/srv/docker-services`. For a guaranteed-consistent copy, stop the container
  first.
- **Prometheus TSDB.** Completed blocks are immutable and safe. The active WAL
  may be partial, so a restore can lose the most recent scrape window.

## Restore

### Prerequisites

You need `restic/password` and `restic/repository` from `secrets/secrets.yaml`.
**Losing the repository password makes every backup permanently unreadable.**
Keep a copy outside this repo — a machine that cannot decrypt sops cannot
restore.

Set up the environment on any host that can reach gmktec:

```bash
export RESTIC_PASSWORD_FILE=/run/secrets/restic/password
export RESTIC_REPOSITORY=$(sudo cat /run/secrets/restic/repository)
```

### Browse

```bash
restic snapshots                      # everything
restic snapshots --path /var/lib/garage/data
restic ls <snapshot-id> | head
```

> **Trap:** all five jobs share one repository, so `latest` means *the newest
> snapshot of any job* — usually `system-state`, which runs last. A restore
> that looks empty is normally this, not a missing backup. Always pin the job:
>
> ```bash
> restic restore latest --path /mnt/immich-data/immich --target /restore
> ```
>
> A second trap: in `restic ls`, arguments after the snapshot ID are treated as
> *directory filters*, and `--path` takes one value. `restic ls latest --path A B`
> silently means "snapshot latest filtered by path A, listing directory B".
> Pass an explicit snapshot ID when listing.

### Restore files

```bash
# Whole path, into a staging directory — never straight over live data
restic restore latest --target /restore --path /mnt/immich-data/immich

# A single file
restic restore latest --target /restore --include /srv/memos/memos_prod.db
```

Always restore to a staging directory, verify, then move the data into place.

### Restore a database

```bash
restic restore latest --target /restore --path /var/backup/dumps

# trigkey's own Postgres (roles and all databases)
zstd -dc /restore/var/backup/dumps/trigkey-postgresql.sql.zst \
  | runuser -u postgres -- psql

# A container's Postgres inside the LXC
zstd -dc /restore/var/backup/dumps/lxc-koito-db.sql.zst \
  | incus exec docker-services -- docker exec -i koito-db psql -U postgres
```

The dumps use `--clean`, so they drop and recreate objects. Stop the consuming
service first.

### Restore Garage

Garage's `data/` directory holds immutable content-addressed blocks. The live
LMDB metadata is *not* backed up — the consistent snapshot under
`meta/snapshots/<timestamp>/` is. To restore, put `data/` back, then replace
`meta/db.lmdb` with the snapshot's copy while Garage is stopped.

```bash
systemctl stop garage
restic restore latest --target /restore --path /var/lib/garage/data
# copy data/ into place, then:
#   rm -rf /var/lib/garage/meta/db.lmdb
#   cp -a /restore/.../meta/snapshots/<timestamp>/* /var/lib/garage/meta/db.lmdb/
systemctl start garage
```

`node_key` and `cluster_layout` are included in the backup — the restored node
keeps its identity.

## Checks

```bash
systemctl list-timers 'restic-backups-*'
systemctl status restic-backups-databases.service
journalctl -u restic-backups-immich.service -n 50

restic snapshots            # newest per job should be from last night
restic stats latest
restic check                # full structural verification
```

On gmktec:

```bash
df -h /mnt/backup           # T7 capacity
systemctl status restic-rest-server.socket
```

## Design notes

**Why not a Garage cluster.** Adding gmktec as a second Garage node was
considered and rejected. Garage's own documentation calls changing
`replication_factor` on a live cluster *"a dangerous operation that is not
officially supported"*, and at `replication_factor = 2` the write quorum is 2 —
every write would fail whenever gmktec is down. Replication is also not a
backup: a delete or corruption propagates immediately. Revisit at three nodes.

**Why append-only is off.** `appendOnly = true` on the REST server would protect
the repository against a compromised trigkey, but it blocks `forget --prune`,
so the repository would grow without bound. Turning it on is a one-line change
in `backup-server.nix`, at the cost of pruning manually on gmktec.

**Single point of failure.** Every backup lives on one external SSD. The
internal 953 GB NVMe in gmktec is nearly empty and can hold a second copy, and
an off-site target is still missing. Neither exists yet.

**History.** Before 2026-08-06 this repo contained `hosts/nixos/trigkey/backup.nix`
defining an Immich-only job, but the file was never imported by any host, its
`RESTIC_REPOSITORY` pointed at a decommissioned address, and its target bucket
did not exist. No backup had ever run.
