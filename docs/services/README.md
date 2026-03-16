# Service inventory

Operational reference for all services. For a high-level overview, see the [main README](../../README.md).

## Trigkey host — Native services

| Service | What it does | Port | Config | Data path |
|---------|-------------|------|--------|-----------|
| [Immich](https://immich.app/) | Photo and video management with mobile auto-upload | 2283 | `hosts/trigkey/immich.nix` | `/mnt/immich-data/immich` |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Bitwarden-compatible password manager (signups disabled) | 8222 | `hosts/common/vaultwarden.nix` | — |
| [Garage S3](https://garagehq.deuxfleurs.fr/) | S3-compatible object storage (LMDB, single-node, cluster-ready) | 3900 (S3), 3901 (RPC) | `hosts/trigkey/garage.nix` | `/var/lib/garage/` |
| Garage WebUI | Web dashboard for Garage bucket and key management | 3909 | `hosts/trigkey/garage-webui.nix` | — |
| [Newt](https://docs.pangolin.dev/) | Pangolin tunnel client — exposes services without open ports | — | `hosts/trigkey/newt.nix` | — |
| [Home Assistant](https://www.home-assistant.io/) | Home automation: TP-Link, Tuya, Apple TV, AirGradient sensor | 8123 | `hosts/optional/homeassistant.nix` | `/var/lib/hass` |
| [Prometheus](https://prometheus.io/) | Metrics collection with 30-day retention (node, container, IoT) | 9090 | `hosts/optional/monitoring.nix` | — |
| [Grafana](https://grafana.com/) | Dashboards for node metrics, container stats, and air quality | 3000 | `hosts/optional/monitoring.nix` | — |
| [Syncthing](https://syncthing.net/) | Bidirectional vault sync between devices (feeds transcription) | 8384 (UI), 22000 | `hosts/optional/syncthing.nix` | `/srv/obsidian/` |

## Trigkey host — Podman containers

| Service | What it does | Port | Config | Data path |
|---------|-------------|------|--------|-----------|
| [Komodo](https://komo.do/) | Container management platform with MongoDB backend | 9120 | `hosts/trigkey/services/komodo.nix` | `/srv/komodo/` |
| [Strava Statistics](https://github.com/robiningelbrecht/strava-statistics) | Athletic activity analytics with daily auto-import (4:05 AM) | 7080 | `hosts/trigkey/services/strava.nix` | `/srv/strava/` |
| [Kavita](https://www.kavitareader.com/) | Web-based manga, comics, and book reader | 5000 | `hosts/trigkey/services/kavita.nix` | `/srv/kavita/` |
| [Memos](https://www.usememos.com/) | Lightweight note-taking app (SQLite) | 5230 | `hosts/trigkey/services/memos.nix` | `/srv/memos` |
| [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) | Music scrobbling aggregator across multiple platforms | 9078 | `hosts/trigkey/services/scrobbler.nix` | `/srv/multi-scrobbler/` |
| [Networking Tools](https://github.com/Lissy93/networking-toolbox) | Web-based DNS, ping, traceroute, and network utilities | 3069 | `hosts/trigkey/services/networking-tools.nix` | — |
| [Termix](https://github.com/LukeGus/Termix) | Multiplayer terminal game | 8080 | `hosts/trigkey/services/termix.nix` | `/srv/termix/` |
| [WhisperX](https://github.com/m-bain/whisperX) | Watched-folder audio transcription with speaker diarization | — | `hosts/trigkey/services/whisper-transcription.nix` | `/srv/transcription/` |

For details on the transcription pipeline, see [transcription.md](transcription.md).

## Docker-services LXC — Docker containers

All containers run inside the `docker-services` NixOS LXC at `10.0.100.10`. Data on the host lives under `/srv/docker-services/` and is mounted into the container via Incus disk devices.

| Service | What it does | Port | Config | Data path (host) |
|---------|-------------|------|--------|-------------------|
| [Koito](https://github.com/gabehf/koito) | Music dashboard and listening analytics (app + PostgreSQL) | 4110 | `hosts/docker-services/services/koito.nix` | `/srv/docker-services/koito/` |
| [Karakeep](https://github.com/karakeep-app/karakeep) | Bookmark manager with full-text search (app + Meilisearch + headless Chrome) | 3088 | `hosts/docker-services/services/karakeep.nix` | `/srv/docker-services/karakeep/` |
| [Dawarich](https://github.com/Freika/dawarich) | Location history tracking and visualization (Rails + PostGIS + Redis + Sidekiq) | 3000 | `hosts/docker-services/services/dawarich.nix` | `/srv/docker-services/dawarich/` |
| [City-Gifs](https://github.com/blindjoe/city-gifs) | Timelapse GIF gallery (read-only, resource-limited) | 3070 | `hosts/docker-services/services/city-gifs.nix` | — |
| [Komodo Periphery](https://komo.do/) | Remote container management agent (pairs with Komodo Core) | 8120 | `hosts/docker-services/services/periphery.nix` | — |
| [cAdvisor](https://github.com/google/cadvisor) | Container metrics collector (scraped by Prometheus) | 9101 | `hosts/docker-services/services/cadvisor.nix` | — |

For details on monitoring, see [monitoring.md](monitoring.md).
