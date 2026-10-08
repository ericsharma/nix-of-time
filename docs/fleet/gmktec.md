# gmktec

The second machine: trigkey's backup target, the `/data` media library, local LLM inference, and remote play of a physical Switch.

```bash
nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo   # from trigkey
rebuild                                                                        # on gmktec itself
```

The `/gmktec` Claude Code skill covers operating it in detail.

| | |
|---|---|
| Address | `192.168.0.51`. Use the IP, not `gmktec.local`: Avahi announces on each interface, so the name can resolve to the podman bridge (`10.88.0.1`) |
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
| Chaptarr | 8789, `chaptarr.local` | Ebooks, copied into trigkey's Kavita library over NFS |
| MeshLLM | 9337, 3131 (loopback) | Local OpenAI-compatible inference |
| Piper | 5000 | Text to speech |
| Papra | 1221, `papra.local` | Document management (SQLite) |
| [Sunshine](../services/sunshine.md) | 47990 UI, + stream ports | Moonlight stream host for the Switch capture card |
| [Pokémon Automation](../services/pokemon-automation.md) | — | Switch automation in the sway session |
| [ACE Typer](../services/switch.md) | 8171 (loopback), `ace.local` | FireRed ACE box codes and live keys through the ESP32-S3 |
| Newt | — | Pangolin tunnel client |
| node exporter, cAdvisor | 9100, 9101 | Scraped by trigkey's Prometheus |

LAN ports admit `192.168.0.0/24` only. LAN names: [Portless](../networking.md#portless--lan-names).

## How it differs from trigkey

1. **Imports are explicit.** Never glob `optional/`. Host-only services live in `hosts/nixos/gmktec/`.
2. **Firewall rules name a source.** Use `extraInputRules` with `ip saddr`, never `openFirewall`. See [Networking](../networking.md#firewall).
3. **Hardware video.** The Vega iGPU does VAAPI for Jellyfin and for Sunshine's encoder. Both use `/dev/dri/renderD128`, so a stream and a transcode compete. trigkey has no GPU config.
4. **It has a graphical session.** `gmktec/sunshine.nix` runs headless sway as a user service purely so Sunshine has something to capture. It is the only compositor in the fleet, and the only reason this host has PipeWire. `users.users.eric.linger` in `../common` is what starts eric's user manager at boot with nobody logged in — Sunshine and sway both depend on that.
5. **A new group reaches user units only after a restart.** eric's user manager keeps the groups it had when it started. A change needs `sudo systemctl restart user@1000.service`, and that restart also stops the sway session. So give a user unit device access with a udev rule (`OWNER="eric"`), as `sunshine.nix` and `pokemon-automation.nix` do.
   - The one group here is `audio`, which no other host needs. With no seat and nobody logged in, logind never applies the uaccess ACL that normally grants `/dev/snd/*`, so without the group WirePlumber finds zero devices. Check and fix: [Sunshine troubleshooting](../services/sunshine.md#troubleshooting).
6. **It has a capture card and a wired controller.** The card at `/dev/video0` is the only USB video device in the fleet. The ESP32-S3 board at `/dev/pa-esp32s3` acts as a wired Pro Controller. Which program holds which device: [Nintendo Switch](../services/switch.md).

## Storage rules

- **`/data` must stay one filesystem.** Sonarr and Radarr import by moving files. Across filesystems a move becomes copy plus delete, doubling IO and briefly the space.
- **Chaptarr is the exception.** Its root folder `/mnt/kavita` is an NFSv4 mount of trigkey's `/srv/kavita/books/books/chaptarr`, so imports are copies. If trigkey was down at boot, run `sudo systemctl start mnt-kavita.mount podman-chaptarr.service`.
- **Media services share group `media`.** `/data` is mode 2775 with setgid. Give a new media service the same absolute paths, `media` as its primary group, `UMask = 0002`, and no private bind mount or second disk.
- **`/mnt/backup` is only for trigkey's restic repository.** No media, no model caches.
- **Nothing on gmktec is backed up.** `/data` can be re-downloaded. Papra's documents in `/srv/papra/app-data/` are not covered either.

## Local inference

- **MeshLLM** serves Qwen3-4B on `127.0.0.1:9337`. Reach it by SSH tunnel. See [MeshLLM](../services/meshllm.md).
- **`llama-cpp` CLI** comes from nixpkgs-unstable, because 25.11's build can't load `gemma4` GGUFs. Start `llama-server` with `--host 0.0.0.0` to use the LAN rule on 8081.
- Both are CPU builds. The iGPU shares DDR4 bandwidth with the CPU, so Vulkan rarely beats 8 threads.
- `eric` is in the `mesh-llm` group, so `llama-cpp` can reuse MeshLLM's 2.5 GB GGUF instead of downloading another copy.
