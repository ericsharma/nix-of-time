# nixos-config

A fully declarative, flake-based NixOS homelab running 20+ self-hosted services on a single Trigkey mini PC (32GB RAM, 512GB SSD). Every service, secret, and system configuration is defined in Nix and version-controlled — one `nixos-rebuild switch` deploys the entire stack.

## What it replaces

| Cloud Service | Self-Hosted Alternative |
|---------------|------------------------|
| Google Photos | [Immich](https://immich.app/) |
| Google Timeline | [Dawarich](https://github.com/Freika/dawarich) |
| 1Password / Bitwarden | [Vaultwarden](https://github.com/dani-garcia/vaultwarden) |
| Kindle / Audible | [Kavita](https://www.kavitareader.com/) |
| Last.fm | [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) |
| Notion | [Memos](https://www.usememos.com/) |
| Pocket / Raindrop | [Karakeep](https://github.com/karakeep-app/karakeep) |
| AWS S3 | [Garage](https://garagehq.deuxfleurs.fr/) |
| Datadog | [Prometheus](https://prometheus.io/) + [Grafana](https://grafana.com/) |

## What it runs

### Photos & Media

- [**Immich**](https://immich.app/) — self-hosted photo and video management with mobile auto-upload
- [**City-Gifs**](https://github.com/blindjoe/city-gifs) — timelapse GIF gallery
- [**Garage S3**](https://garagehq.deuxfleurs.fr/) — S3-compatible distributed object storage (LMDB-backed, cluster-ready)

### Reading & Music

- [**Kavita**](https://www.kavitareader.com/) — web-based manga, comics, and book reader with library management
- [**Multi-Scrobbler**](https://github.com/FoxxMD/multi-scrobbler) — music scrobbling aggregator across multiple platforms
- [**Koito**](https://github.com/gabehf/koito) — music dashboard and listening analytics

### Fitness & Location

- [**Strava Statistics**](https://github.com/robiningelbrecht/strava-statistics) — athletic activity analytics with daily auto-import
- [**Dawarich**](https://github.com/Freika/dawarich) — location history tracking and visualization (Rails + PostGIS + Sidekiq)

### Smart Home & Environment

- [**Home Assistant**](https://www.home-assistant.io/) — home automation hub controlling TP-Link smart plugs, Tuya devices, Apple TV, and Android TV
- [**AirGradient ONE**](https://www.airgradient.com/) — real-time air quality sensor (PM2.5, CO2, temperature, humidity, VOC, NOx) feeding metrics into Prometheus and Home Assistant dashboards

### AI & Automation

- [**WhisperX**](https://github.com/m-bain/whisperX) — watched-folder audio transcription with speaker diarization (CPU, INT8)
- [**Syncthing**](https://syncthing.net/) — bidirectional file sync between devices, powering the transcription pipeline

#### Workflow: drop audio, get a transcript

```
Laptop (Obsidian)                    Trigkey (headless)
┌────────────────────┐               ┌────────────────────────────┐
│ Drop audio into    │   Syncthing   │ inotifywait detects file   │
│ Transcriptions/    │──────────────►│ WhisperX transcribes       │
│                    │               │ .md with speaker labels    │
│ Transcript + audio │◄──────────────│ Syncthing syncs back       │
│ appear in Obsidian │               │                            │
└────────────────────┘               └────────────────────────────┘
```

Drop an audio file into your Obsidian vault. Syncthing syncs it to trigkey, WhisperX transcribes it with timestamps and speaker diarization, and the markdown transcript appears alongside the original audio — ready to read and play back inline.

### Notes & Knowledge

- [**Memos**](https://www.usememos.com/) — lightweight note-taking app (SQLite-backed)
- [**Karakeep**](https://github.com/karakeep-app/karakeep) — bookmark manager with full-text search (Meilisearch + headless Chrome)
- [**Vaultwarden**](https://github.com/dani-garcia/vaultwarden) — self-hosted Bitwarden-compatible password manager

### Infrastructure & Observability

- [**Prometheus**](https://prometheus.io/) + [**Grafana**](https://grafana.com/) — metrics collection and dashboarding with 30-day retention
- [**Node Exporter**](https://github.com/prometheus/node_exporter) + [**cAdvisor**](https://github.com/google/cadvisor) — host and container metrics across both runtimes
- [**AirGradient**](https://www.airgradient.com/) **sensor → JSON exporter → Prometheus → Grafana** — IoT air quality monitoring in the same pipeline as infrastructure metrics
- [**Komodo**](https://komo.do/) — container management platform with remote [Periphery](https://komo.do/) agents
- [**Newt**](https://docs.pangolin.dev/) — Pangolin tunnel client exposing services without opening home network ports
- [**Networking Tools**](https://github.com/Lissy93/networking-toolbox) — web-based DNS, ping, traceroute utilities
- [**Termix**](https://github.com/LukeGus/Termix) — multiplayer terminal game

## Architecture

```
Trigkey Mini PC (32GB RAM, 512GB SSD)
┌──────────────────────────────────────────────────┐
│  NixOS (declarative, flake-based)                │
│                                                  │
│  Native services:                                │
│    Immich · Vaultwarden · Garage S3              │
│    Home Assistant · Syncthing                    │
│    Prometheus + Grafana                          │
│                                                  │
│  Podman containers (single-service):             │
│    Komodo · Strava · Kavita · Memos              │
│    Scrobbler · WhisperX · Termix                 │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │  Incus LXC (NixOS, nested Docker)          │  │
│  │  Multi-container stacks:                   │  │
│  │    Dawarich (app + db + redis + worker)     │  │
│  │    Karakeep (app + search + chrome)         │  │
│  │    Koito (app + postgres)                   │  │
│  │    City-Gifs · Periphery · cAdvisor         │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

## Engineering decisions

- **NixOS flakes** — the entire system is declarative and reproducible. One `nixos-rebuild switch` deploys everything. No imperative setup steps, no configuration drift.
- **Dual container runtimes** — Podman for single-container services on the host. Docker inside an Incus NixOS LXC for multi-container stacks that need inter-container DNS. Each runtime is chosen for what it does best.
- **sops-nix** — secrets are encrypted with age and committed to git. Each host decrypts with its own SSH-derived key. No external secret store, no plaintext in the repo.
- **Newt tunnel** — all services bind to localhost and are exposed externally via [Pangolin](https://pangolin.dev/). No ports open on the home network.

## Quick start

```bash
# Rebuild trigkey (aliased)
rebuild                  # sudo nixos-rebuild switch --flake ~/nixos-config#$(hostname)

# Deploy to docker-services container (aliased)
rebuild-docker           # nixos-rebuild switch --flake ~/nixos-config#docker-services --target-host root@10.0.100.10

# Test without making it the boot default
sudo nixos-rebuild test --flake .#trigkey
```

## Directory conventions

| Path | Purpose |
|------|---------|
| `hosts/common/` | Shared system config (users, SSH, sops, Podman, Incus) |
| `hosts/optional/` | Opt-in modules imported per-host as needed |
| `hosts/<name>/` | Per-host config (boot, networking, hardware) |
| `hosts/<name>/services/` | OCI container definitions for that host |
| `home/common/` | Shared home-manager config (shell, git, packages) |
| `home/optional/` | Opt-in home-manager modules imported per-host as needed |
| `home/<name>/` | Per-host home-manager overrides |
| `secrets/` | sops-encrypted secrets (age) |

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
