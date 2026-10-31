# Syncthing

Two-way sync of the Obsidian vaults between trigkey and personal devices. It backs up the vaults and carries files for [transcription](transcription.md).

Web UI: loopback only, `ssh -L 8384:127.0.0.1:8384 eric@trigkey` then `http://localhost:8384` · Module: `hosts/nixos/optional/syncthing.nix`

| Vault | Path on trigkey |
|-------|-----------------|
| Work | `/srv/obsidian/Work` |
| Brain 2.0 | `/srv/obsidian/Brain 2.0` |

Each vault is its own shared folder, paired with the matching vault on the laptop. New files reach every paired device within seconds.

Ports: 8384 UI (127.0.0.1), 22000 TCP and UDP sync (LAN and tailnet), 21027 UDP discovery (LAN).
