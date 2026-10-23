# trigkey

The anchor of the fleet. Most services, all three runtime tiers, and the `docker-services` LXC run here.

```bash
rebuild                                      # deploy
sudo nixos-rebuild test --flake .#trigkey    # try it without changing the boot default
```

| | |
|---|---|
| Address | `192.168.0.202` |
| Hardware | Trigkey mini PC, AMD x86_64, 32 GB RAM, ~15 W idle |
| Storage | 512 GB NVMe, plus an external drive for Immich |
| Config | `hosts/nixos/trigkey/` |

## Rules

- **`git add` new `.nix` files before `rebuild`.** The flake skips untracked modules without any error.
- **trigkey imports all of `hosts/nixos/optional/`.** Never copy that import block to another host.
- **Editing `optional/` can change gmktec too.** If gmktec imports the module, deploy both.
- **Machine-agnostic services go in `optional/`**, even if only trigkey runs them. Hardware- or storage-bound ones (Immich, Garage, backup, the Incus launcher) go in `hosts/nixos/trigkey/`.
- **Sudo is passwordless** for `eric`. Run `systemctl` and `journalctl` directly.

## Tiers on this host

1. **Native:** Immich, Vaultwarden, Garage, Home Assistant, Prometheus, Grafana, Syncthing, TapMap, Jellyfin, Icecast, EternaTV.
2. **Podman:** Kavita, Memos, Multi-Scrobbler, Termix, WhisperX, PiroueSync, Dreeve, Networking Tools, Ladder, FlareSolverr.
3. **Docker in the LXC:** see [docker-services](docker-services.md).

To choose a tier: [Architecture](../architecture.md#when-to-use-which).

## Storage

| Path | Holds |
|------|-------|
| `/mnt/immich-data/immich` | Immich library, on the external drive |
| `/var/lib/garage/{data,meta}` | Every Garage bucket |
| `/srv/docker-services/` | LXC data, mounted in with UID shifting |
| `/srv/<service>/` | Podman service data |
| `/srv/jellyfin/media` | FUSE view of the `guitar` bucket, not real storage |
| `/srv/obsidian/` | Syncthing vaults |

## Backup

Nightly restic jobs push to gmktec between 01:30 and 04:30. The last job prunes the whole repository. See [Backup and restore](../services/backup.md).

The USB optical drive for `/dvd-rip` is at `/dev/sr0`. See [the guitar library](../media/guitar-library.md).

## tmux workspace

trigkey keeps one tmux session, `main`, with a shell window and a claude window for each host. You attach to it from the laptop or from E.T. on the iPhone.

| Window | Runs |
|--------|------|
| `trigkey`, `trigkey-claude` | a shell, `claude` |
| `gmktec`, `gmktec-claude` | `ssh gmktec`, then `claude` |
| `mac-mini`, `mac-mini-claude` | `ssh mac-mini`, then `claude` |

- **`ws`** makes the session, or attaches to it if it exists. It is safe to run again. Module: `home/trigkey/workspace.nix`.
- **To add a host**, add one entry to `remotes` in that module. It also becomes a `~/.ssh/config` alias.
- **`~/.ssh/config` is made by home-manager.** It is read-only. Change `remotes`, not the file.
- **Sessions come back after a reboot.** The workspace is manymux sessions on every machine (`ws`). A checkpoint every 15 minutes, restored when trigkey starts; Claude sessions come back with `claude --continue`. Module: `home/trigkey/manymux-checkpoint.nix`. (The tmux workspace and tmux-persist.nix were removed 2026-10-22.)
