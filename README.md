# Nix of Time

NixOS configuration for a self-hosted homelab. One mini PC, ~25 services, fully declarative.

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
Trigkey Mini PC
├── CPU:     AMD (x86_64)
├── RAM:     32 GB
├── Storage: 512 GB NVMe SSD + external drive
├── OS:      NixOS 25.11
└── Power:   ~15W idle
```

---

## The stack

### Photos, media & storage

| Service | What it does |
|---------|-------------|
| [Immich](https://immich.app/) | Photo and video management with mobile auto-upload |
| [City-Gifs](https://github.com/blindjoe/city-gifs) | Timelapse GIF gallery |
| [Garage S3](https://garagehq.deuxfleurs.fr/) | S3-compatible object storage (LMDB-backed, cluster-ready) |

### Reading & music

| Service | What it does |
|---------|-------------|
| [Kavita](https://www.kavitareader.com/) | Manga, comics, and book reader |
| [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) | Music scrobbling aggregator |
| [Koito](https://github.com/gabehf/koito) | Music dashboard and listening analytics |

### Fitness & location

| Service | What it does |
|---------|-------------|
| [Strava Statistics](https://github.com/robiningelbrecht/strava-statistics) | Athletic activity analytics with daily auto-import |
| [Dawarich](https://github.com/Freika/dawarich) | Location history tracking and visualization (Rails + PostGIS) |

### Smart home & environment

| Service | What it does |
|---------|-------------|
| [Home Assistant](https://www.home-assistant.io/) | TP-Link, Tuya, Apple TV, Android TV, AirGradient |
| [AirGradient ONE](https://www.airgradient.com/) | PM2.5, CO2, temperature, humidity, VOC, NOx |

### AI & automation

| Service | What it does |
|---------|-------------|
| [WhisperX](https://github.com/m-bain/whisperX) | Watched-folder audio transcription with speaker diarization |
| [Syncthing](https://syncthing.net/) | Bidirectional file sync |
| [PiroueSync](https://github.com/ericsharma/PiroueSync) | Synchronized music player for ballet classes |

### Notes & knowledge

| Service | What it does |
|---------|-------------|
| [Memos](https://www.usememos.com/) | Lightweight note-taking (SQLite) |
| [Karakeep](https://github.com/karakeep-app/karakeep) | Bookmark manager with full-text search (Meilisearch + headless Chrome) |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Bitwarden-compatible password manager |

### Infrastructure & observability

| Service | What it does |
|---------|-------------|
| [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) | Metrics and dashboarding with 30-day retention |
| [Node Exporter](https://github.com/prometheus/node_exporter) + [cAdvisor](https://github.com/google/cadvisor) | Host and container metrics |
| [Komodo](https://komo.do/) | Container management with [Periphery](https://komo.do/) agents |
| [Newt](https://docs.pangolin.dev/) | Pangolin tunnel — zero open ports |
| [TapMap](https://github.com/olalie/tapmap) | Real-time network connection visualizer |
| [Networking Tools](https://github.com/Lissy93/networking-toolbox) | DNS, ping, traceroute |
| [Termix](https://github.com/LukeGus/Termix) | Browser-based terminal |

> Full inventory with ports, configs, and data paths: [docs/services/](docs/services/README.md)

---

## Architecture

```
Trigkey Mini PC (32 GB RAM, 512 GB SSD)
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
│  │  Komodo · Strava · Kavita · Memos · Scrobbler            │  │
│  │  WhisperX · Termix · PiroueSync · Networking Tools       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Incus LXC (NixOS guest, nested Docker)                  │  │
│  │  Dawarich · Karakeep · Koito · City-Gifs                 │  │
│  │  Periphery · cAdvisor                                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

Three runtime tiers:

- **Native NixOS modules** for services with first-class NixOS support. Type-checked, integrated with systemd.
- **Podman** for single-container services on the host. No daemon, no Docker socket, rootless-ready.
- **Docker inside an Incus NixOS LXC** for multi-container stacks that need Docker's built-in DNS for inter-container resolution. The LXC has its own NixOS configuration, deployed via `nixos-rebuild --target-host`.

---

## Quick start

```bash
# Rebuild trigkey
rebuild                  # sudo nixos-rebuild switch --flake ~/nixos-config#$(hostname)

# Deploy to docker-services LXC
rebuild-docker           # nixos-rebuild switch --flake .#docker-services --target-host root@10.0.100.10

# Test without making it the boot default
sudo nixos-rebuild test --flake .#trigkey
```

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
