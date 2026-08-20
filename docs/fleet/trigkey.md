# trigkey

The anchor of the fleet. Every user-facing service runs here, and the
`docker-services` LXC runs inside it.

| | |
|---|---|
| Address | `192.168.0.202` |
| Hardware | Trigkey mini PC, AMD x86_64, 32 GB RAM |
| Storage | 512 GB NVMe SSD, plus an external drive for Immich |
| OS | NixOS 25.11 |
| Power | About 15 W at idle |
| Deploy | `rebuild` |
| Config | `hosts/nixos/trigkey/` |

## What lives here, and where

trigkey imports **every** module under `hosts/nixos/optional/` through
`lib.filesystem.listFilesRecursive`. Those modules have no enable flags, and
several need this machine's hardware.

**Never copy that import block to another host.** Any other host lists its
imports one by one. `hosts/nixos/gmktec/default.nix` shows the pattern.

| Directory | Holds |
|-----------|-------|
| `hosts/nixos/trigkey/` | Only things tied to this physical box: hardware, networking, the Incus launcher, and storage-coupled services (Immich, Garage, backup) |
| `hosts/nixos/optional/` | The shared library of opt-in service modules, native and Podman alike |
| `hosts/nixos/common/` | Shared system config: users, SSH, sops, Podman, Incus |

If a service is machine-agnostic, it belongs in `optional/` even though only
trigkey runs it today. That is what makes a future host cheap.

## The three runtime tiers

All three tiers live on this one machine.

1. **Native NixOS modules** — Immich, Vaultwarden, Garage, Home Assistant,
   Prometheus, Grafana, Syncthing, TapMap, Jellyfin, Icecast, EternaTV.
2. **Podman containers**, single service, via `virtualisation.oci-containers` —
   Kavita, Memos, Multi-Scrobbler, Termix, WhisperX, PiroueSync, Dreeve,
   Networking Tools.
3. **Docker inside an Incus LXC** — see [docker-services](docker-services.md).

Pick the tier with the table in
[Architecture](../architecture.md#when-to-use-which).

## Storage

| Path | Holds |
|------|-------|
| `/mnt/immich-data/immich` | Immich photo and video library, on the external drive |
| `/var/lib/garage/{data,meta}` | Every Garage bucket |
| `/srv/docker-services/` | Persistent data for the LXC, mounted in with UID shifting |
| `/srv/<service>/` | Per-service data for the Podman tier |
| `/srv/jellyfin/media` | FUSE mountpoint for the `guitar` bucket — not real storage |
| `/srv/obsidian/` | The Syncthing vault that feeds transcription |

## Backup

trigkey is the machine that gets backed up. Nightly restic jobs push to the
REST server on gmktec, all into one repository, grouped by host and paths.

The job order matters: the last job carries the retention pass for the whole
repository. See [Backup and restore](../services/backup.md).

## Operating notes

- **Passwordless sudo** for `eric` in `wheel`. Run `rebuild`, `nh os switch`,
  `systemctl` and `journalctl` directly. The threat-model difference is small
  on a single-user, key-only host, and it keeps automated rebuilds
  non-interactive.
- **A new `.nix` file must be `git add`ed before a rebuild.** The flake sees
  tracked files only. An untracked module is skipped in silence.
- **Editing `optional/` affects gmktec too**, if gmktec imports the module you
  changed. Redeploy both.
- The USB optical drive for [`/dvd-rip`](../media/guitar-library.md) is on this
  host, at `/dev/sr0`.

## Deploy

```bash
rebuild                                  # switch
sudo nixos-rebuild test --flake .#trigkey   # try it without changing the boot default
```
