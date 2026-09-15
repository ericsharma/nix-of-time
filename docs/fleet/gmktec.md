# gmktec

The second machine: trigkey's backup target, the `/data` media library, and local LLM inference.

```bash
nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo   # from trigkey
rebuild                                                                        # on gmktec itself
```

The `/gmktec` Claude Code skill covers operating it in detail.

| | |
|---|---|
| Address | `192.168.0.51` |
| Hardware | GMKtec mini PC, Ryzen 7 5825U (16 threads), Vega iGPU |
| Memory | 32 GB + 14 GB zram, no swap partition |
| Storage | 1 TB NVMe (ext4); Samsung T7 931 GB external SSD at `/mnt/backup` |
| Config | `hosts/nixos/gmktec/` |

## What it runs

| Service | Port | Purpose |
|---------|------|---------|
| restic REST server | 8000 (trigkey only) | Stores trigkey's backups on the T7 |
| Jellyfin | 8096 | The `/data` library, VAAPI transcoding |
| SABnzbd, Prowlarr, Sonarr, Radarr | 8080, 9696, 8989, 7878 | Fill `/data/media` |
| MeshLLM | 9337, 3131 (loopback) | Local OpenAI-compatible inference |
| Piper | 5000 | Text to speech |
| Papra | 1221, `papra.local` | Document management (SQLite) |
| Newt | — | Pangolin tunnel client |
| node exporter, cAdvisor | 9100, 9101 | Scraped by trigkey's Prometheus |

LAN ports admit `192.168.0.0/24` only. LAN names: [Portless](../networking.md#portless--lan-names).

## How it differs from trigkey

1. **Imports are explicit.** Never glob `optional/`. Host-only services live in `hosts/nixos/gmktec/`.
2. **Firewall rules name a source.** Use `extraInputRules` with `ip saddr`, never `openFirewall`. See [Networking](../networking.md#firewall).
3. **Hardware video.** The Vega iGPU does VAAPI for Jellyfin. trigkey has no GPU config.

## Storage rules

- **`/data` must stay one filesystem.** Sonarr and Radarr import by moving files. Across filesystems a move becomes copy plus delete, doubling IO and briefly the space.
- **Media services share group `media`.** `/data` is mode 2775 with setgid. Give a new media service the same absolute paths, `media` as its primary group, `UMask = 0002`, and no private bind mount or second disk.
- **`/mnt/backup` is only for trigkey's restic repository.** No media, no model caches.
- **Nothing on gmktec is backed up.** `/data` can be re-downloaded. Papra's documents in `/srv/papra/app-data/` are not covered either.

## Local inference

- **MeshLLM** serves Qwen3-4B on `127.0.0.1:9337`. Reach it by SSH tunnel. See [MeshLLM](../services/meshllm.md).
- **`llama-cpp` CLI** comes from nixpkgs-unstable, because 25.11's build can't load `gemma4` GGUFs. Start `llama-server` with `--host 0.0.0.0` to use the LAN rule on 8081.
- Both are CPU builds. The iGPU shares DDR4 bandwidth with the CPU, so Vulkan rarely beats 8 threads.
- `eric` is in the `mesh-llm` group, so `llama-cpp` can reuse MeshLLM's 2.5 GB GGUF instead of downloading another copy.
