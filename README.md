# Nix of Time

NixOS configuration for a self-hosted homelab. Two mini PCs, ~35 services, fully declarative.

![NixOS 25.11](https://img.shields.io/badge/NixOS-25.11-5277C3?logo=nixos&logoColor=white)

---

## Contents

- [Hardware](#hardware)
- [The stack](#the-stack)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Directory conventions](#directory-conventions)
- [Documentation](#documentation)
- [Documentation site](#documentation-site)

---

## Hardware

```
trigkey — Trigkey Mini PC          (192.168.0.202)
├── CPU:     AMD (x86_64)
├── RAM:     32 GB
├── Storage: 512 GB NVMe SSD + external drive
├── OS:      NixOS 25.11
├── Role:    every service; hosts the docker-services LXC
└── Power:   ~15W idle

gmktec — GMKtec Mini PC             (192.168.0.51)
├── CPU:     AMD Ryzen 7 5825U (16 threads)
├── RAM:     32 GB + 14 GB zram
├── Storage: 1 TB NVMe SSD (ext4)
├── OS:      NixOS 25.11
├── Disk 2:  Samsung T7 931 GB external SSD → /mnt/backup
└── Role:    restic backup target; Usenet stack; Jellyfin; local inference
```

`gmktec` publishes nothing to the internet — it has no Newt, so every service on
it is LAN-only or loopback-only. It imports `../common` explicitly, module by
module: the monitoring exporters, the restic REST server that receives trigkey's
backups, the Usenet stack, a second Jellyfin, and MeshLLM.

See [docs/fleet/](docs/fleet/trigkey.md) for a page per machine.

---

## The stack

Categorized high-level overview. For descriptions, ports, config files, and data paths see the [full service inventory](docs/services/README.md).

### Photos, media & storage
- [Immich](https://immich.app/)
- [Jellyfin](https://jellyfin.org/) — two servers, see [docs/media/jellyfin.md](docs/media/jellyfin.md)
- [Garage S3](https://garagehq.deuxfleurs.fr/)
- [City-Gifs](https://github.com/blindjoe/city-gifs)
- [Cobalt](https://github.com/imputnet/cobalt)

### Streaming — EternaTV
- [Icecast](https://icecast.org/) + [Liquidsoap](https://www.liquidsoap.info/) — `radio.ericsharma.xyz`
- EternaTV video channels + Hono auth sidecar — `video.ericsharma.xyz`
- Full detail: [docs/media/eternatv.md](docs/media/eternatv.md)

### Usenet & library (gmktec)
- [SABnzbd](https://sabnzbd.org/) · [Prowlarr](https://prowlarr.com/) · [Sonarr](https://sonarr.tv/) · [Radarr](https://radarr.video/)
- Full detail: [docs/services/usenet.md](docs/services/usenet.md)

### Reading & music
- [Kavita](https://www.kavitareader.com/)
- [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler)
- [Koito](https://github.com/gabehf/koito)

### Fitness & location
- [Dreeve](https://github.com/dreeveapp/dreeve) — formerly Statistics for Strava
- [Endurain](https://codeberg.org/endurain-project/endurain)
- [Dawarich](https://github.com/Freika/dawarich)

### Smart home & environment
- [Home Assistant](https://www.home-assistant.io/)
- [AirGradient ONE](https://www.airgradient.com/)

### AI & automation
- [WhisperX](https://github.com/m-bain/whisperX)
- MeshLLM — local OpenAI-compatible inference on gmktec
- [Syncthing](https://syncthing.net/)
- [PiroueSync](https://github.com/ericsharma/PiroueSync)

### Notes & knowledge
- [Memos](https://www.usememos.com/)
- [Karakeep](https://github.com/karakeep-app/karakeep)
- [Vaultwarden](https://github.com/dani-garcia/vaultwarden)

### Infrastructure & observability
- [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/)
- [Node Exporter](https://github.com/prometheus/node_exporter) + [cAdvisor](https://github.com/google/cadvisor)
- [Newt](https://docs.pangolin.dev/)
- [TapMap](https://github.com/olalie/tapmap)
- [Networking Tools](https://github.com/Lissy93/networking-toolbox)
- [Termix](https://github.com/LukeGus/Termix)
- [Portless](https://portless.sh) — `*.local` names on the LAN
- [Rybbit](https://github.com/rybbit-io/rybbit) — web analytics
- PGWeb — PostgreSQL web UI

### Sites & apps
- Belle Watson Studios — static SPA
- ericsharma.xyz — personal site
- Options Ledger — options portfolio dashboard
- This documentation site — see [Documentation site](#documentation-site)

---

## Architecture

```
trigkey — Trigkey Mini PC (32 GB RAM, 512 GB SSD)
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  NixOS 25.11 — flake-based                                     │
│  Secrets: sops-nix (age-encrypted, committed to git)           │
│  Exposure: Pangolin tunnel                                     │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Native NixOS services                                   │  │
│  │  Immich · Vaultwarden · Garage S3 · Home Assistant       │  │
│  │  Syncthing · Prometheus · Grafana · TapMap · Jellyfin    │  │
│  │  Icecast+Liquidsoap · EternaTV · nginx static sites      │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Podman containers (single-service, host network)        │  │
│  │  Dreeve · Kavita · Memos · Scrobbler                     │  │
│  │  WhisperX · Termix · PiroueSync · Networking Tools       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Incus LXC (NixOS guest, nested Docker) — 10.0.100.10    │  │
│  │  Dawarich · Karakeep · Koito · City-Gifs                 │  │
│  │  Cobalt · Rybbit · Endurain · cAdvisor                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘

gmktec — GMKtec Mini PC (32 GB RAM, 1 TB SSD)
┌────────────────────────────────────────────────────────────────┐
│  NixOS 25.11 — same flake, separate nixosConfiguration         │
│  Imports ../common + named modules only. No Newt: LAN only.    │
│                                                                │
│  restic REST server ← trigkey's nightly backups (T7 SSD)       │
│  SABnzbd · Prowlarr · Sonarr · Radarr → /data → Jellyfin       │
│  MeshLLM (CPU inference) · Piper · Portless (*.local)          │
│  node exporter, scraped by trigkey's Prometheus over the LAN   │
└────────────────────────────────────────────────────────────────┘
```

The repository uses three runtime tiers. See the detailed decision criteria and "When to use which" table in [docs/architecture.md](docs/architecture.md#when-to-use-which).

---

## Quick start

```bash

# Rebuild the physical Trigkey host (native services + Podman + Incus)

rebuild                  # sudo nixos-rebuild switch --flake ~/nixos-config#trigkey


# Deploy changes to the docker-services LXC (multi-container Docker stacks)

rebuild-docker           # nixos-rebuild switch --flake .#docker-services --target-host root@10.0.100.10


# Deploy changes to the gmktec mini PC

nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo


# Test a change on trigkey without making it the boot default

sudo nixos-rebuild test --flake .#trigkey
```


> **Note**: `trigkey`, `docker-services`, and `gmktec` are separate `nixosConfigurations` in the same flake. Changes to one do not affect the others until deployed.


---

## Directory conventions

| Path | Purpose |
|------|---------|
| `hosts/nixos/common/` | Shared NixOS system config (users, SSH, sops, Podman, Incus) |
| `hosts/nixos/optional/` | Shared library of opt-in NixOS service modules — native and Podman alike — imported per-host as needed |
| `hosts/nixos/<name>/` | Per-host NixOS config (boot, networking, hardware, machine-specific services) |
| `hosts/nixos/docker-services/services/` | Docker container definitions for the docker-services LXC |
| `hosts/darwin/` | macOS hosts via nix-darwin (`common/`, `optional/`, per-machine dirs) — scaffolding only until Macs are wired in |
| `home/common/` | Shared home-manager config (shell, git, packages) |
| `home/optional/` | Opt-in home-manager modules |
| `home/<name>/` | Per-host home-manager overrides |
| `inventory.nix` | Cross-host facts (host → IP) shared by modules like Prometheus scrape config |
| `secrets/` | sops-encrypted secrets (age) |

---

## Documentation

All of this is also published as a browsable site at
**[docs.ericsharma.xyz](https://docs.ericsharma.xyz)**, built from these same
files by `docs-site/`. See [Documentation site](#documentation-site) below.

**Start here**

| Topic | Link |
|-------|------|
| Architecture and deployment strategies | [docs/architecture.md](docs/architecture.md) |
| Networking and exposure (Pangolin, firewall, `*.local`) | [docs/networking.md](docs/networking.md) |
| Secrets management | [docs/secrets.md](docs/secrets.md) |
| Service inventory (ports, configs, data paths) | [docs/services/](docs/services/README.md) |

**The fleet**

| Host | Link |
|------|------|
| trigkey — the anchor | [docs/fleet/trigkey.md](docs/fleet/trigkey.md) |
| gmktec — backup target, Usenet, inference | [docs/fleet/gmktec.md](docs/fleet/gmktec.md) |
| docker-services — the Incus LXC | [docs/fleet/docker-services.md](docs/fleet/docker-services.md) |

**Media**

| Topic | Link |
|-------|------|
| Overview — which machine holds what | [docs/media/](docs/media/README.md) |
| Garage object storage and every bucket | [docs/media/garage.md](docs/media/garage.md) |
| The guitar library (DVD → Garage → Jellyfin) | [docs/media/guitar-library.md](docs/media/guitar-library.md) |
| Jellyfin — why there are two servers | [docs/media/jellyfin.md](docs/media/jellyfin.md) |
| EternaTV — the radio and video streams | [docs/media/eternatv.md](docs/media/eternatv.md) |
| Usenet stack (SABnzbd, Prowlarr, Sonarr, Radarr) | [docs/services/usenet.md](docs/services/usenet.md) |

**Operations**

| Topic | Link |
|-------|------|
| Adding a new service | [docs/adding-a-service.md](docs/adding-a-service.md) |
| Adding a new machine | [docs/adding-a-machine.md](docs/adding-a-machine.md) |
| Backup and restore (restic → gmktec) | [docs/services/backup.md](docs/services/backup.md) |
| Monitoring (Prometheus, Grafana) | [docs/services/monitoring.md](docs/services/monitoring.md) |
| Audio transcription (WhisperX) | [docs/services/transcription.md](docs/services/transcription.md) |
| Syncthing file sync | [docs/services/syncthing.md](docs/services/syncthing.md) |
| Local LLM inference (MeshLLM) | [docs/services/meshllm.md](docs/services/meshllm.md) |
| Claude Code skills | [docs/claude-skills.md](docs/claude-skills.md) |

## Documentation site

`docs-site/` is an [Astro Starlight](https://starlight.astro.build/) site built
from the markdown in `docs/`. It is served by nginx on `127.0.0.1:4209` from the
Nix store, and fronted by Pangolin at `docs.ericsharma.xyz`. The module is
`hosts/nixos/optional/docs-site.nix`.

`docs/` stays the source of truth. `docs-site/scripts/sync-docs.mjs` copies
those files into the Starlight content collection at build time, adds the
frontmatter Starlight needs, and rewrites relative `.md` links into site URLs.
Write ordinary GitHub-readable markdown in `docs/` and the site follows.

```bash
cd docs-site
corepack pnpm install
corepack pnpm run dev      # http://localhost:4321
corepack pnpm run build    # what the Nix derivation runs
```

A new page appears in the sidebar only when it is listed in the `sidebar` array
in `docs-site/astro.config.mjs`, except under `services/`, which is
auto-generated from the directory.
