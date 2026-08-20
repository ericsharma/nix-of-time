# gmktec

The second machine. It runs no user-facing service that is reachable from
outside the LAN, and it is the backup target for trigkey.

| | |
|---|---|
| Address | `192.168.0.51` |
| Hardware | GMKtec mini PC, AMD Ryzen 7 5825U, 16 threads |
| Memory | 32 GB, plus 14 GB zram |
| Storage | 1 TB NVMe SSD (ext4), plus a Samsung T7 931 GB external SSD at `/mnt/backup` |
| OS | NixOS 25.11 |
| Config | `hosts/nixos/gmktec/` |

```bash
nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo
```

The `/gmktec` Claude Code skill covers the differences from trigkey in detail.

## What it runs

| Service | Port | Purpose |
|---------|------|---------|
| restic REST server | 8000 | Receives trigkey's nightly backups onto the T7 |
| SABnzbd | 8080 | Usenet downloader |
| Prowlarr | 9696 | Indexer manager |
| Sonarr | 8989 | TV |
| Radarr | 7878 | Film |
| Jellyfin | 8096 | The `/data` library |
| MeshLLM | 9337 API, 3131 console | Local OpenAI-compatible inference, CPU |
| Piper | — | Text to speech |
| node exporter, textfile metrics | 9100 | Scraped by trigkey's Prometheus |

## How it differs from trigkey

These are the four differences that catch people out.

1. **Imports are explicit.** gmktec lists every module by name. It must not
   glob `optional/`, because those modules assume trigkey's hardware.
2. **No Newt.** Nothing here can be published through Pangolin. Everything is
   LAN only or loopback only.
3. **Scoped nftables rules, not `allowedTCPPorts`.** Every open port names a
   source subnet. See [Networking](../networking.md#firewall).
4. **It has hardware video acceleration.** The 5825U's Vega iGPU does VAAPI
   transcoding for Jellyfin. trigkey has no `hardware.graphics` block at all.

## Storage

One ext4 filesystem on the internal NVMe holds the whole media tree, and that
is a hard requirement rather than a preference:

```
/data/usenet/incomplete    SABnzbd work area
/data/usenet/complete/*    finished downloads, one directory per category
/data/media/{tv,movies}    the library
```

Sonarr and Radarr finish an import by **moving** the file out of
`/data/usenet/complete` into the library. A move is atomic and instant within
one filesystem. Across a boundary it becomes a copy plus a delete, which
doubles the IO and, briefly, the space.

Everything is group `media`, mode 2775 with the setgid bit, so a new file
inherits the group and services that run as different users can still read and
write each other's output. Give any future media service the same absolute
paths, `media` as its **primary** group, and `UMask = 0002`. Never give one of
them a private bind mount or a second disk.

`/mnt/backup` is the T7 and is reserved for trigkey's restic repository. Do not
put media there.

Nothing on gmktec is backed up. Every file under `/data` is re-downloadable,
and `/mnt/backup` is the destination for someone else's backup, not a source.

## Local inference

MeshLLM serves an OpenAI-compatible API on `127.0.0.1:9337` with Qwen3-4B. It
has **no firewall rule on purpose** — reach it over an SSH tunnel.

`llama-cpp` is installed as CLI tools only, from nixpkgs-unstable rather than
25.11. Stable ships a build that predates the `gemma4` architecture and fails
to load those GGUFs. llama.cpp adds architectures constantly, so a stable
channel is always months behind whatever model you just downloaded.

Both are CPU-only builds. The Vega iGPU shares DDR4 bandwidth with the CPU, so
a Vulkan build rarely beats 8 threads here and pulls in a mesa userspace.

`eric` is in the `mesh-llm` group so `llama-cpp` can reuse the GGUF already on
disk instead of downloading a second 2.5 GB copy.

## Swap

No swap partition. `zramSwap.enable = true` covers the rare spike without a
permanent on-disk partition, on a machine with 32 GB of RAM.

## See also

- [Usenet stack](../services/usenet.md) — the full arr configuration
- [MeshLLM](../services/meshllm.md)
- [Backup and restore](../services/backup.md)
- [Networking](../networking.md#portless--lan-names) — the `*.local` names
