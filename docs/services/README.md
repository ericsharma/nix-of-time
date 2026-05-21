# Service inventory

Operational reference for all services. For a high-level overview, see the [main README](../../README.md).


> **Documentation status**: Core services are documented below. Additional services and detailed guides live in this folder. See [hermes-agent.md](hermes-agent.md) and [tailscale.md](tailscale.md) for examples.
## Trigkey host — Native services

| Service | What it does | Port | Config | Data path |
|---------|-------------|------|--------|-----------|
| [Immich](https://immich.app/) | Photo and video management with mobile auto-upload | 2283 | `hosts/nixos/trigkey/immich.nix` | `/mnt/immich-data/immich` |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Bitwarden-compatible password manager (signups disabled) | 8222 | `hosts/nixos/optional/vaultwarden.nix` | — |
| [Garage S3](https://garagehq.deuxfleurs.fr/) | S3-compatible object storage (LMDB, single-node, cluster-ready) | 3900 (S3), 3901 (RPC) | `hosts/nixos/trigkey/garage.nix` | `/var/lib/garage/` |
| Garage WebUI | Web dashboard for Garage bucket and key management | 3909 | `hosts/nixos/trigkey/garage-webui.nix` | — |
| [Newt](https://docs.pangolin.dev/) | Pangolin tunnel client — exposes services without open ports | — | `hosts/nixos/trigkey/newt.nix` | — |
| [Home Assistant](https://www.home-assistant.io/) | Home automation: TP-Link, Tuya, Apple TV, AirGradient sensor | 8123 | `hosts/nixos/optional/homeassistant.nix` | `/var/lib/hass` |
| [Prometheus](https://prometheus.io/) | Metrics collection with 30-day retention (node, container, IoT) | 9090 | `hosts/nixos/optional/monitoring.nix` | — |
| [Grafana](https://grafana.com/) | Dashboards for node metrics, container stats, and air quality | 3000 | `hosts/nixos/optional/monitoring.nix` | — |
| [Syncthing](https://syncthing.net/) | Bidirectional vault sync between devices (feeds transcription) | 8384 (UI), 22000 | `hosts/nixos/optional/syncthing.nix` | `/srv/obsidian/` |
| [TapMap](https://github.com/olalie/tapmap) | Real-time network connection visualizer (Dash/Plotly) | 8050 | `hosts/nixos/optional/tapmap.nix` | `/srv/tapmap/` |
|| [Hermes Agent](hermes-agent.md) | Nous Research AI agent (CLI + gateway) | — | `hosts/nixos/optional/hermes-agent.nix` | `/var/lib/hermes/.hermes` |
|| [Tailscale](tailscale.md) | Mesh VPN with SSH support | UDP 41641 | `hosts/nixos/optional/tailscale.nix` | — |

## Trigkey host — Podman containers

| Service | What it does | Port | Config | Data path |
|---------|-------------|------|--------|-----------|
| [Komodo](https://komo.do/) | Container management platform with MongoDB backend | 9120 | `hosts/nixos/optional/komodo.nix` | `/srv/komodo/` |
| [Strava Statistics](https://github.com/robiningelbrecht/strava-statistics) | Athletic activity analytics with daily auto-import (4:05 AM) | 7080 | `hosts/nixos/optional/strava.nix` | `/srv/strava/` |
| [Kavita](https://www.kavitareader.com/) | Web-based manga, comics, and book reader | 5000 | `hosts/nixos/optional/kavita.nix` | `/srv/kavita/` |
| [Memos](https://www.usememos.com/) | Lightweight note-taking app (SQLite) | 5230 | `hosts/nixos/optional/memos.nix` | `/srv/memos` |
| [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) | Music scrobbling aggregator across multiple platforms | 9078 | `hosts/nixos/optional/scrobbler.nix` | `/srv/multi-scrobbler/` |
| [Networking Tools](https://github.com/Lissy93/networking-toolbox) | Web-based DNS, ping, traceroute, and network utilities | 3069 | `hosts/nixos/optional/networking-tools.nix` | — |
| [PiroueSync](https://github.com/ericsharma/PiroueSync) | Synchronized music playback for ballet classes (built from private repo) | 4203 | `hosts/nixos/optional/pirousync.nix` | — |
| [Termix](https://github.com/LukeGus/Termix) | Browser-based terminal | 8080 | `hosts/nixos/optional/termix.nix` | `/srv/termix/` |
| [WhisperX](https://github.com/m-bain/whisperX) | Watched-folder audio transcription with speaker diarization | — | `hosts/nixos/optional/whisper-transcription.nix` | `/srv/transcription/` |

For details on the transcription pipeline, see [transcription.md](transcription.md).

## Docker-services LXC — Docker containers

All containers run inside the `docker-services` NixOS LXC at `10.0.100.10`. Data on the host lives under `/srv/docker-services/` and is mounted into the container via Incus disk devices.

| Service | What it does | Port | Config | Data path (host) |
|---------|-------------|------|--------|-------------------|
| [Koito](https://github.com/gabehf/koito) | Music dashboard and listening analytics (app + PostgreSQL) | 4110 | `hosts/nixos/docker-services/services/koito.nix` | `/srv/docker-services/koito/` |
| [Karakeep](https://github.com/karakeep-app/karakeep) | Bookmark manager with full-text search (app + Meilisearch + headless Chrome) | 3088 | `hosts/nixos/docker-services/services/karakeep.nix` | `/srv/docker-services/karakeep/` |
| [Dawarich](https://github.com/Freika/dawarich) | Location history tracking and visualization (Rails + PostGIS + Redis + Sidekiq) | 3000 | `hosts/nixos/docker-services/services/dawarich.nix` | `/srv/docker-services/dawarich/` |
| [City-Gifs](https://github.com/blindjoe/city-gifs) | Timelapse GIF gallery (read-only, resource-limited) | 3070 | `hosts/nixos/docker-services/services/city-gifs.nix` | — |
| [Komodo Periphery](https://komo.do/) | Remote container management agent (pairs with Komodo Core) | 8120 | `hosts/nixos/docker-services/services/periphery.nix` | — |
| [cAdvisor](https://github.com/google/cadvisor) | Container metrics collector (scraped by Prometheus) | 9101 | `hosts/nixos/docker-services/services/cadvisor.nix` | — |

For details on monitoring, see [monitoring.md](monitoring.md).

---

## Additional services (not yet fully documented)

These services exist in the configuration but are not yet detailed in the main inventory tables:

### Trigkey host — Additional native / optional services
- **Hermes Agent** — This AI agent runtime (`hosts/nixos/optional/hermes-agent.nix`)
- **Options Ledger** — (`hosts/nixos/optional/options-ledger.nix`)
- **PGWeb** — PostgreSQL web UI (`hosts/nixos/optional/pgweb.nix`)
- **Tailscale** — VPN (`hosts/nixos/optional/tailscale.nix`)
- **Radio** & **Radio Video** — (`hosts/nixos/optional/radio*.nix`)
- **Belle Watson Studios** — Monitoring dashboards (`hosts/nixos/optional/belle-watson-studios.nix`)

### Docker-services LXC — Additional containers
- **Cobalt**, **Keeper**, **Rybbit** and others under `hosts/nixos/docker-services/services/`

For full details, inspect the corresponding `.nix` files.

### Hermes Agent
- **Description**: Nous Research Hermes Agent (CLI + gateway service)
- **Config**: `hosts/nixos/optional/hermes-agent.nix`
- **Notes**: Runs as systemd service `hermes-agent`. State at `/var/lib/hermes/.hermes`. User `eric` is in the `hermes` group for shared access. Currently configured with Grok 4.3 via xAI OAuth. No inbound ports.

### Tailscale
- **Description**: Mesh VPN with SSH support
- **Config**: `hosts/nixos/optional/tailscale.nix`
- **Port**: UDP 41641 (open via `openFirewall`)
- **Notes**: Uses sops secret for auth key. Enables `--ssh` for passwordless SSH over Tailscale.

