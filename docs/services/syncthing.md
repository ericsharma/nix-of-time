# Syncthing

Syncthing (`hosts/optional/syncthing.nix`) provides bidirectional file sync between trigkey and personal devices. Serves as both a backup for Obsidian vaults and the transport layer for the [transcription workflow](transcription.md).

## Endpoints

| Endpoint | Port |
|----------|------|
| Web UI | `http://trigkey:8384` |
| Sync (TCP+UDP) | 22000 |
| Discovery (UDP) | 21027 |

## Synced directories

| Vault | Path on trigkey |
|-------|-----------------|
| Work | `/srv/obsidian/Work` |
| Brain 2.0 | `/srv/obsidian/Brain 2.0` |

Each vault is configured as a separate Syncthing shared folder, paired with the corresponding vault directory on the laptop. New files (including transcriptions) sync to all paired devices within seconds.
