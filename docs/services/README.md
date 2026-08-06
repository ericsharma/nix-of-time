# Service inventory

Detailed operational reference for all services (ports, config locations, data paths, etc.). For a categorized high-level overview, see the [main README](../../README.md).

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
| [Hermes Agent](hermes-agent.md) | Nous Research AI agent (CLI + gateway) | — | `hosts/nixos/optional/hermes-agent.nix` | `/var/lib/hermes/.hermes` |
| [Tailscale](tailscale.md) | Mesh VPN with SSH support | UDP 41641 | `hosts/nixos/optional/tailscale.nix` | — |
| [Jellyfin](https://jellyfin.org/) | Media server for the Garage-backed `guitar` library (LAN) | 8096 | `hosts/nixos/optional/jellyfin.nix` | `/srv/jellyfin/media` (rclone mount) |
| Options Ledger | Options portfolio dashboard (SPA + Yahoo quote proxy) | 4205 (SPA), 4206 (API) | `hosts/nixos/optional/options-ledger.nix` | `/var/lib/options-ledger-server/` |
| PGWeb | PostgreSQL web UI (sessions + bookmarks) | 5435 | `hosts/nixos/optional/pgweb.nix` | — |
| Radio | Icecast stream of Garage-backed music | 8000 | `hosts/nixos/optional/radio.nix` | `/var/lib/radio/` |
| Radio Video | HLS video stream with session-gated capture | 8088 (HLS) | `hosts/nixos/optional/radio-video.nix` | `/var/lib/radio-video/` |
| EternaTV Sidecar | Hono sidecar session-gating Radio Video capture | 8090 | `hosts/nixos/optional/eternatv-sidecar.nix` | — |
| Belle Watson Studios | Static Vite SPA served by nginx from the Nix store | 4204 | `hosts/nixos/optional/belle-watson-studios.nix` | — |

## Trigkey host — Podman containers

| Service | What it does | Port | Config | Data path |
|---------|-------------|------|--------|-----------|
| [Dreeve](https://github.com/dreeveapp/dreeve) | Athletic activity analytics (formerly Statistics for Strava). Files import mode; activity files synced from Endurain every 15 min | 7080 | `hosts/nixos/optional/dreeve.nix` | `/srv/strava/` |
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
| [Dawarich](https://github.com/Freika/dawarich) | Location history tracking and visualization (Rails + PostGIS + Redis + Sidekiq) | 3000 (LAN: trigkey:3030 via nginx proxy in `hosts/nixos/optional/dawarich.nix`) | `hosts/nixos/docker-services/services/dawarich.nix` | `/srv/docker-services/dawarich/` |
| [City-Gifs](https://github.com/blindjoe/city-gifs) | Timelapse GIF gallery (read-only, resource-limited) | 3070 | `hosts/nixos/docker-services/services/city-gifs.nix` | — |
| [cAdvisor](https://github.com/google/cadvisor) | Container metrics collector (scraped by Prometheus) | 9101 | `hosts/nixos/docker-services/services/cadvisor.nix` | — |
| [Cobalt](https://github.com/imputnet/cobalt) | Self-hosted media download API (pinned image) | 9000 | `hosts/nixos/docker-services/services/cobalt.nix` | — |
| [Rybbit](https://github.com/rybbit-io/rybbit) | Web analytics (backend + client + ClickHouse + PostgreSQL) | 3001 (API), 3002 (web) | `hosts/nixos/docker-services/services/rybbit.nix` | `/srv/docker-services/rybbit/` |
| [Endurain](https://codeberg.org/endurain-project/endurain) | Fitness tracking with native Garmin Connect sync (app + PostgreSQL + Redis) | 8080 | `hosts/nixos/docker-services/services/endurain.nix` | `/srv/docker-services/endurain/` |

## Gmktec host — Native services

| Service | What it does | Port | Config | Data path |
|---------|-------------|------|--------|-----------|
| [restic REST server](backup.md) | Receives trigkey's nightly backups onto the T7 external SSD | 8000 (trigkey only) | `hosts/nixos/gmktec/backup-server.nix` | `/mnt/backup/restic` |
| [MeshLLM](meshllm.md) | Local OpenAI-compatible LLM inference (CPU, Qwen3-4B) | 9337 (API), 3131 (console) — both loopback | `hosts/nixos/gmktec/meshllm.nix` | `/var/lib/mesh-llm/` |

For details on monitoring, see [monitoring.md](monitoring.md).
