# Backup and restore

trigkey backs up nightly with restic to a REST server on gmktec's T7 SSD. That is the only copy of trigkey's data that survives losing trigkey.

## Set up a shell (on trigkey)

Every command below needs this first:

```bash
export RESTIC_PASSWORD_FILE=/run/secrets/restic/password
export RESTIC_REPOSITORY=$(sudo cat /run/secrets/restic/repository)
```

## Check last night's run

```bash
systemctl list-timers 'restic-backups-*'
restic snapshots                                   # newest per job should be from last night
journalctl -u restic-backups-immich.service -n 50  # one job's log
ssh eric@192.168.0.51 'df -h /mnt/backup'          # T7 free space
```

Deeper: `restic stats latest`, `restic check`.

## Restore

1. **Find the snapshot for one job path.** `latest` alone means the newest snapshot of *any* job, usually `system-state`. An empty-looking restore is almost always this.
   ```bash
   restic snapshots --path /var/lib/garage/data
   restic ls <snapshot-id> | head
   ```
2. **Restore into `/restore`, never over live data.**
   ```bash
   restic restore latest --path /mnt/immich-data/immich --target /restore
   restic restore latest --target /restore --include /srv/memos/memos_prod.db   # one file
   ```
3. **Stop the service, verify the files, move them into place.**

### A database

```bash
restic restore latest --target /restore --path /var/backup/dumps

# trigkey's Postgres (all roles and databases)
zstd -dc /restore/var/backup/dumps/trigkey-postgresql.sql.zst | runuser -u postgres -- psql

# a container's Postgres in the LXC
zstd -dc /restore/var/backup/dumps/lxc-koito-db.sql.zst \
  | incus exec docker-services -- docker exec -i koito-db psql -U postgres
```

Dumps use `--clean` (drop and recreate), so stop the consuming service first.

### Garage

The backup holds `data/` and a consistent metadata snapshot, not the live LMDB file.

```bash
systemctl stop garage
restic restore latest --target /restore --path /var/lib/garage/data
# copy data/ into place, then:
#   rm -rf /var/lib/garage/meta/db.lmdb
#   cp -a /restore/.../meta/snapshots/<timestamp>/* /var/lib/garage/meta/db.lmdb/
systemctl start garage
```

`node_key` and `cluster_layout` are included, so the node keeps its identity.

### Traps

- **Losing `restic/password` makes every backup unreadable.** Keep a copy outside this repo. A machine that can't decrypt sops can't restore.
- **`restic ls latest --path A B`** treats `B` as a directory filter, and `--path` takes one value. Pass an explicit snapshot ID.
- **ClickHouse** (Rybbit, ~11 GB) is backed up as files. Stop the container first if you need a guaranteed-consistent copy.
- **Prometheus WAL** may be partial, so a restore can lose the last scrape window.

## What is backed up

| Job | Time | Contents |
|-----|------|----------|
| `databases` | 01:30 | `pg_dumpall` of trigkey Postgres + dumps of the four LXC Postgres containers |
| `immich` | 02:00 | `/mnt/immich-data/immich` (~104 GB) |
| `garage` | 03:00 | `/var/lib/garage/data` + a metadata snapshot |
| `docker-services` | 04:00 | `/srv/docker-services`: Rybbit, Dawarich, Karakeep, Koito, Endurain |
| `system-state` | 04:30 | Home Assistant, Grafana, Hermes, both Prometheus TSDBs, `/srv` service dirs |

- One repository: `/mnt/backup/restic/trigkey`, encrypted. gmktec stores blocks it can't read. Port 8000 admits trigkey only.
- Retention: `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`, grouped by host and paths.
- Only `system-state` prunes, so pruning runs once a night. It also runs `restic check --read-data-subset=2%`, covering the whole repo in about 50 days.
- Config: `hosts/nixos/trigkey/backup.nix`, `hosts/nixos/gmktec/backup-server.nix`.

Not backed up, on purpose:

| Path | Why |
|------|-----|
| `/var/lib/private/ollama` | 13 GB of re-downloadable model weights |
| `/var/lib/containers` | Podman image cache, rebuilt from pinned tags |
| `/var/lib/incus` | LXC rootfs; declarative, and its data is bind-mounted |
| `/srv/jellyfin`, `/var/lib/radio*/…` | rclone views of Garage, already in the `garage` job (skipped by `--one-file-system`) |

Nothing on gmktec itself is backed up. See [gmktec](../fleet/gmktec.md#storage-rules).

## Decisions

- **No Garage cluster.** At `replication_factor = 2` every write fails while gmktec is down, and changing it on a live cluster is unsupported. Replication also copies deletes. Revisit at three nodes.
- **Append-only is off.** It would protect against a compromised trigkey but blocks `forget --prune`. Turning it on is one line in `backup-server.nix`, plus manual pruning on gmktec.
- **One disk, no off-site copy.** Every backup is on a single T7. A second copy and an off-site target don't exist yet.
