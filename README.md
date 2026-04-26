# Nix of Time

> You don't need the cloud.

This repository is proof: 25+ self-hosted services that replace Google Photos, 1Password, Notion, Datadog, and more — all running on a single $300 mini PC in my living room. Every config is in git. Every secret is encrypted. One command deploys everything.

No monthly bills. No vendor lock-in. No terms of service changes at 2 AM. Just Nix.

![NixOS 25.11](https://img.shields.io/badge/NixOS-25.11-5277C3?logo=nixos&logoColor=white)
![Nix Flakes](https://img.shields.io/badge/flakes-enabled-blue?logo=nixos)
![Services](https://img.shields.io/badge/services-25+-green)
![Cloud Cost](https://img.shields.io/badge/cloud_cost-$0/month-brightgreen)
![Secrets](https://img.shields.io/badge/secrets-sops--nix-yellow)
![Open Ports](https://img.shields.io/badge/open_ports-0-red)

---

## Contents

- [What it replaces](#what-it-replaces)
- [The hardware](#the-hardware)
- [How it works together](#how-it-works-together)
- [The stack](#the-stack)
- [Architecture](#architecture)
- [Why NixOS?](#why-nixos)
- [Quick start](#quick-start)
- [Documentation](#documentation)

---

## What it replaces

One Trigkey mini PC. Zero cloud subscriptions. Here's what it runs instead:

| Cloud Service | Self-Hosted Alternative | ~Monthly Cost Replaced |
|---------------|------------------------|----------------------|
| Google Photos | [Immich](https://immich.app/) | $3 (Google One) |
| Google Timeline | [Dawarich](https://github.com/Freika/dawarich) | free, but your location data goes to Google |
| 1Password / Bitwarden | [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | $3 |
| Kindle + Audible | [Kavita](https://www.kavitareader.com/) | $25 (Kindle Unlimited + Audible) |
| Last.fm | [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) + [Koito](https://github.com/gabehf/koito) | free, but your listening data stays with Spotify |
| Notion | [Memos](https://www.usememos.com/) | $10 |
| Pocket / Raindrop | [Karakeep](https://github.com/karakeep-app/karakeep) | $3 |
| AWS S3 | [Garage](https://garagehq.deuxfleurs.fr/) | $5+ |
| Datadog / Grafana Cloud | [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) | $15+ |
| Otter.ai / transcription | [WhisperX](https://github.com/m-bain/whisperX) | $17 |
| Dropbox / iCloud Drive | [Syncthing](https://syncthing.net/) | $12 |
| Custom cloud deployment | [PiroueSync](https://github.com/ericsharma/PiroueSync) | priceless |

**Hardware cost:** ~$300 one-time. **Cloud cost replaced:** ~$90+/month. The mini PC pays for itself in under four months.

---

## The hardware

```
Trigkey Mini PC
├── CPU:     AMD (x86_64)
├── RAM:     32 GB
├── Storage: 512 GB NVMe SSD + external drive for photos
├── OS:      NixOS 25.11 (unstable)
├── Power:   ~15W idle
└── Size:    fits in your palm
```

This runs everything. Twenty-five services, two container runtimes, a full monitoring stack, a home automation hub, and an IoT air quality sensor — all on a machine smaller than a paperback book.

---

## How it works together

Services don't just run side by side. They compose into workflows that automate real parts of daily life.

### Voice memos become searchable knowledge

Drop an audio file into your Obsidian vault. A transcript appears next to it — with timestamps, speaker labels, and an embedded audio player.

```
Phone / Laptop                         Trigkey (headless)
┌─────────────────────────┐            ┌──────────────────────────────────┐
│                         │  Syncthing │                                  │
│  Record a voice memo    │───────────►│  inotifywait detects new file    │
│  Drop it into           │            │          │                       │
│  Obsidian/Transcriptions│            │          ▼                       │
│                         │            │  WhisperX transcribes (CPU, INT8)│
│  ┌───────────────────┐  │            │  Speaker diarization via         │
│  │ meeting-notes.md  │  │  Syncthing │  pyannote + HuggingFace         │
│  │ meeting-notes.m4a │◄─┼────────────│          │                       │
│  │                   │  │            │          ▼                       │
│  │ Timestamped       │  │            │  Markdown with ![[audio]] embed  │
│  │ transcript with   │  │            │  Speaker labels + timestamps     │
│  │ inline playback   │  │            │                                  │
│  └───────────────────┘  │            └──────────────────────────────────┘
└─────────────────────────┘
```

No cloud API. No per-minute pricing. No sending your private conversations to a third party. The model runs locally on the CPU.

### The air you breathe, on a dashboard

An AirGradient ONE sensor sits in the room and measures everything: PM2.5, CO2, temperature, humidity, VOC, and NOx. That data flows into the same monitoring pipeline as server metrics.

```
AirGradient ONE (WiFi)
  │
  │  HTTP /measures/current (JSON)
  ▼
Prometheus (JSON exporter, 30s scrape)
  │
  ├──► Grafana dashboard
  │    PM2.5 · CO2 · Temperature · Humidity · VOC · NOx
  │    Same interface as CPU/memory/container dashboards
  │
  └──► Home Assistant
       Automations, alerts, historical trends
       Alongside TP-Link smart plugs, Tuya devices,
       Apple TV, and Android TV controls
```

Infrastructure monitoring and environmental monitoring in one pipeline. Server health and air quality on the same screen.

### Ballet class music, deployed with `nixos-rebuild`

PiroueSync is a synchronized music player I built for ballet classes. It's a private repo pulled as a Nix flake input, built from source on the server, and deployed as a Podman container — with the same `nixos-rebuild switch` that manages every other service.

```
flake.nix                              Trigkey
┌─────────────────────────┐            ┌──────────────────────────────────┐
│ pirousync = {           │            │                                  │
│   url = "git+ssh://     │  nix flake │  systemd: pirousync-build        │
│     github.com/         │──update───►│    Copy source from Nix store    │
│     ericsharma/         │            │    Inject secrets from sops-nix  │
│     PiroueSync";        │            │    podman build from Dockerfile  │
│   flake = false;        │            │          │                       │
│ };                      │            │          ▼                       │
└─────────────────────────┘            │  podman-pirousync container      │
                                       │    Port 4203                     │
                                       │    Auto-restarts on update       │
                                       └──────────────────────────────────┘
```

Update the flake input, rebuild, and the new version is live. No CI/CD pipeline. No container registry. The Nix store *is* the pipeline.

### Fitness tracking without Strava owning your data

Strava Statistics pulls activity data daily at 4:05 AM, builds analytics locally, and serves a personal dashboard. Your running, cycling, and workout history — owned by you, not a VC-funded startup's data lake.

```
Strava API
  │
  │  Daily auto-import (4:05 AM)
  ▼
Strava Statistics (Podman)
  │
  ├── Activity analytics dashboard (port 7080)
  ├── Historical trends and training load
  └── Data stored locally at /srv/strava/
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
| [Kavita](https://www.kavitareader.com/) | Manga, comics, and book reader with library management |
| [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) | Music scrobbling aggregator across platforms |
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
| [Syncthing](https://syncthing.net/) | Bidirectional file sync powering the transcription pipeline |
| [PiroueSync](https://github.com/ericsharma/PiroueSync) | Synchronized music player for ballet classes (custom-built) |

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
| [Node Exporter](https://github.com/prometheus/node_exporter) + [cAdvisor](https://github.com/google/cadvisor) | Host and container metrics across both runtimes |
| [Komodo](https://komo.do/) | Container management with remote [Periphery](https://komo.do/) agents |
| [Newt](https://docs.pangolin.dev/) | Pangolin tunnel — zero open ports on the home network |
| [TapMap](https://github.com/olalie/tapmap) | Real-time network connection visualizer |
| [Networking Tools](https://github.com/Lissy93/networking-toolbox) | DNS, ping, traceroute utilities |
| [Termix](https://github.com/LukeGus/Termix) | Browser-based terminal |

> Full service inventory with ports, config paths, and data directories: [docs/services/](docs/services/README.md)

---

## Architecture

```
Trigkey Mini PC (32 GB RAM, 512 GB SSD, ~15W idle)
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  NixOS 25.11 — fully declarative, flake-based                  │
│  Secrets: sops-nix (age-encrypted, committed to git)           │
│  Exposure: Pangolin tunnel (zero open ports)                   │
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
│  │  For multi-container stacks needing inter-container DNS   │  │
│  │                                                           │  │
│  │  Dawarich (app + PostGIS + Redis + Sidekiq)              │  │
│  │  Karakeep (app + Meilisearch + headless Chrome)          │  │
│  │  Koito (app + PostgreSQL)                                │  │
│  │  City-Gifs · Periphery · cAdvisor                        │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

**Three runtime tiers, chosen deliberately:**

- **Native NixOS modules** for services with first-class NixOS support (Immich, Vaultwarden, Grafana). Declarative, type-checked, integrated with systemd.
- **Podman** for single-container services on the host. No daemon, no Docker socket exposure, rootless-ready.
- **Docker inside an Incus NixOS LXC** for multi-container stacks that need Docker's built-in DNS for inter-container resolution. The LXC runs its own NixOS configuration, deployed via `nixos-rebuild --target-host`. Deleting and recreating the container preserves all data — it's just another `nixos-rebuild switch` away.

---

## Why NixOS?

Most homelabs run Docker Compose. You write a YAML file, run `docker-compose up`, and things mostly work — until they don't. A dependency updates and breaks something. You SSH in and tweak a config file manually. Months later, you can't remember what you changed or why. Your "infrastructure as code" is really infrastructure as a pile of YAML files and prayers.

NixOS is different. The entire system — every package, every service, every firewall rule, every systemd unit — is declared in one place and built atomically. `nixos-rebuild switch` doesn't "apply changes." It builds a complete new system generation and switches to it. If something breaks, `nixos-rebuild switch --rollback` takes you back in seconds. Not "undo the last change" — literally boot into the previous system.

**Why this matters for a homelab:**

- **No configuration drift.** There is no "I SSHed in and tweaked something." The repo *is* the system. If it's not in the repo, it's not on the machine.
- **Secrets in git, safely.** [sops-nix](https://github.com/Mic92/sops-nix) encrypts secrets with age keys derived from each host's SSH key. Secrets are committed alongside the configs that use them. No external secret store, no `.env` files floating around.
- **Zero open ports.** Every service binds to localhost. [Pangolin](https://pangolin.dev/) tunnels expose them externally via [Newt](https://docs.pangolin.dev/). Your home IP is never in a DNS record. Port scans find nothing.
- **Reproducible across machines.** Add a new host to `flake.nix`, write its config, rebuild. The same packages, same versions, same behavior. The flake lockfile pins everything.

This isn't the easy path. NixOS has a learning curve and the Nix language takes getting used to. But once it clicks, you never want to go back to imperative configuration. Your homelab becomes a git repo that you can reason about, diff, review, and roll back — like software.

---

## Quick start

```bash
# Rebuild trigkey (aliased)
rebuild                  # sudo nixos-rebuild switch --flake ~/nixos-config#$(hostname)

# Deploy to docker-services container (aliased)
rebuild-docker           # nixos-rebuild switch --flake ~/nixos-config#docker-services --target-host root@10.0.100.10

# Test without making it the boot default
sudo nixos-rebuild test --flake .#trigkey
```

### Directory conventions

| Path | Purpose |
|------|---------|
| `hosts/common/` | Shared system config (users, SSH, sops, Podman, Incus) |
| `hosts/optional/` | Shared library of opt-in service modules — native NixOS and Podman alike — imported per-host as needed |
| `hosts/<name>/` | Per-host config (boot, networking, hardware, machine-specific services) |
| `hosts/docker-services/services/` | Docker container definitions for the docker-services LXC |
| `home/common/` | Shared home-manager config (shell, git, packages) |
| `home/optional/` | Opt-in home-manager modules |
| `home/<name>/` | Per-host home-manager overrides |
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
