# Nix of Time

NixOS configuration for a self-hosted homelab. Two mini PCs, ~25 services, fully declarative.

![NixOS 25.11](https://img.shields.io/badge/NixOS-25.11-5277C3?logo=nixos&logoColor=white)

---

## Contents

- [Hardware](#hardware)
- [The stack](#the-stack)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Directory conventions](#directory-conventions)
- [Documentation](#documentation)

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
└── Role:    onboarded 2026-08-06; base config and metrics only
```

`gmktec` runs no services yet. It imports `../common` and the monitoring
exporters, nothing else.

---

## The stack

Categorized high-level overview. For descriptions, ports, config files, and data paths see the [full service inventory](docs/services/README.md).

### Photos, media & storage
- [Immich](https://immich.app/)
- [City-Gifs](https://github.com/blindjoe/city-gifs)
- [Garage S3](https://garagehq.deuxfleurs.fr/)

### Reading & music
- [Kavita](https://www.kavitareader.com/)
- [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler)
- [Koito](https://github.com/gabehf/koito)

### Fitness & location
- [Strava Statistics](https://github.com/robiningelbrecht/strava-statistics)
- [Dawarich](https://github.com/Freika/dawarich)

### Smart home & environment
- [Home Assistant](https://www.home-assistant.io/)
- [AirGradient ONE](https://www.airgradient.com/)

### AI & automation
- [WhisperX](https://github.com/m-bain/whisperX)
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
│  │  Syncthing · Prometheus · Grafana · TapMap               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Podman containers (single-service, host network)        │  │
│  │  Strava · Kavita · Memos · Scrobbler                     │  │
│  │  WhisperX · Termix · PiroueSync · Networking Tools       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Incus LXC (NixOS guest, nested Docker)                  │  │
│  │  Dawarich · Karakeep · Koito · City-Gifs                 │  │
│  │  Cobalt · Rybbit · cAdvisor                              │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘

gmktec — GMKtec Mini PC (32 GB RAM, 1 TB SSD)
┌────────────────────────────────────────────────────────────────┐
│  NixOS 25.11 — same flake, separate nixosConfiguration          │
│  Imports ../common + monitoring exporters only                  │
│  Scraped by trigkey's Prometheus over the LAN                   │
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

| Topic | Link |
|-------|------|
| Architecture and deployment strategies | [docs/architecture.md](docs/architecture.md) |
| Secrets management | [docs/secrets.md](docs/secrets.md) |
| Service inventory (ports, configs, data paths) | [docs/services/](docs/services/README.md) |
| Monitoring (Prometheus, Grafana) | [docs/services/monitoring.md](docs/services/monitoring.md) |
| Audio transcription (WhisperX) | [docs/services/transcription.md](docs/services/transcription.md) |
| Syncthing file sync | [docs/services/syncthing.md](docs/services/syncthing.md) |
| Adding a new service | [docs/adding-a-service.md](docs/adding-a-service.md) |
| Adding a new machine | [docs/adding-a-machine.md](docs/adding-a-machine.md) |
| Claude Code skills | [docs/claude-skills.md](docs/claude-skills.md) |
