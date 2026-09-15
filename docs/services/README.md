# Service inventory

Every service with its port, module, and data path. Module paths are relative to `hosts/nixos/`.

Host pages: [trigkey](../fleet/trigkey.md) · [gmktec](../fleet/gmktec.md) · [docker-services](../fleet/docker-services.md) · Media: [overview](../media/README.md) · Exposure: [networking](../networking.md)

## trigkey — native

| Service | What | Port | Module | Data |
|---------|------|------|--------|------|
| [Immich](https://immich.app/) | Photos and video, mobile upload | 2283 | `trigkey/immich.nix` | `/mnt/immich-data/immich` |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Password manager, signups off | 8222 | `optional/vaultwarden.nix` | — |
| [Garage S3](../media/garage.md) | Object storage | 3900 S3, 3901 RPC, 3902 web, 3903 admin | `trigkey/garage.nix` | `/var/lib/garage/` |
| Garage WebUI | Bucket and key dashboard | 3909 | `trigkey/garage-webui.nix` | — |
| [Newt](https://docs.pangolin.dev/) | Pangolin tunnel client | — | `trigkey/newt.nix` | — |
| [Home Assistant](https://www.home-assistant.io/) | Home automation, AirGradient sensor | 8123 | `optional/homeassistant.nix` | `/var/lib/hass` |
| [Prometheus](monitoring.md) | Metrics, 90d; air quality 100y | 9090, 9091 | `optional/monitoring.nix` | `/var/lib/prometheus2`, `/var/lib/prometheus-airgradient` |
| [Grafana](monitoring.md) | Dashboards | 3000 | `optional/monitoring.nix` | `/var/lib/grafana` |
| [Syncthing](syncthing.md) | Vault sync, feeds transcription | 8384 UI, 22000 | `optional/syncthing.nix` | `/srv/obsidian/` |
| [TapMap](https://github.com/olalie/tapmap) | Live network connection map | 8050 | `optional/tapmap.nix` | `/srv/tapmap/` |
| [Hermes Agent](hermes-agent.md) | AI agent, CLI + gateway | — | `optional/hermes-agent.nix` | `/var/lib/hermes/.hermes` |
| [Tailscale](tailscale.md) | Mesh VPN with SSH | UDP 41641 | `optional/tailscale.nix` | — |
| [Jellyfin](../media/jellyfin.md) | Guitar library, server 1 of 2 | 8096 | `optional/jellyfin.nix` | `/srv/jellyfin/media` (rclone mount) |
| Options Ledger | Options dashboard + quote proxy | 4205 SPA, 4206 API | `optional/options-ledger.nix` | `/var/lib/options-ledger-server/` |
| PGWeb | PostgreSQL web UI | 5435 | `optional/pgweb.nix` | — |
| [Radio](../media/eternatv.md) | Icecast stream | 8000 | `optional/radio.nix` | `/var/lib/radio/` |
| [Radio Video](../media/eternatv.md) | HLS video channels | 8088 HLS, 8089 API (no auth) | `optional/radio-video.nix` | `/var/lib/radio-video/` |
| [EternaTV sidecar](../media/eternatv.md) | Session gate for captures | 8090 | `optional/eternatv-sidecar.nix` | Postgres `eternatv` |
| Belle Watson Studios | Static SPA | 4204 | `optional/belle-watson-studios.nix` | — |
| ericsharma.xyz | Personal site | 4208 | `optional/ericsharma-xyz.nix` | — |
| Docs site | This documentation | 4209 | `optional/docs-site.nix` | — |

## trigkey — Podman

| Service | What | Port | Module | Data |
|---------|------|------|--------|------|
| [Dreeve](https://github.com/dreeveapp/dreeve) | Activity analytics; pulls Endurain files every 15 min | 7080 | `optional/dreeve.nix` | `/srv/strava/` |
| [Kavita](https://www.kavitareader.com/) | Books, manga, comics | 5000 | `optional/kavita.nix` | `/srv/kavita/` |
| [Ladder](ladder.md) | Paywall-stripping proxy, `ladder.local`, no auth | 4210 | `optional/ladder.nix` | stateless |
| [FlareSolverr](ladder.md) | Cloudflare solver for Ladder, no auth | 8191 | `optional/flaresolverr.nix` | stateless |
| [Memos](https://www.usememos.com/) | Notes (SQLite) | 5230 | `optional/memos.nix` | `/srv/memos` |
| [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) | Scrobble aggregator | 9078 | `optional/scrobbler.nix` | `/srv/multi-scrobbler/` |
| [Networking Tools](https://github.com/Lissy93/networking-toolbox) | DNS, ping, traceroute in a browser | 3069 | `optional/networking-tools.nix` | — |
| [PiroueSync](https://github.com/ericsharma/PiroueSync) | Synced music playback for ballet class | 4203 | `optional/pirousync.nix` | — |
| [Termix](https://github.com/LukeGus/Termix) | Browser terminal | 8080 | `optional/termix.nix` | `/srv/termix/` |
| [WhisperX](transcription.md) | Watched-folder transcription | — | `optional/whisper-transcription.nix` | `/srv/transcription/` |

## docker-services LXC

All run inside the LXC at `10.0.100.10`. The stateful ones keep data on trigkey in `/srv/docker-services/<service>/`.

| Service | What | Port | Module |
|---------|------|------|--------|
| [Koito](https://github.com/gabehf/koito) | Listening analytics (app + Postgres) | 4110 | `docker-services/services/koito.nix` |
| [Karakeep](https://github.com/karakeep-app/karakeep) | Bookmarks (app + Meilisearch + Chrome) | 3088 | `docker-services/services/karakeep.nix` |
| [Dawarich](https://github.com/Freika/dawarich) | Location history (Rails + PostGIS + Redis + Sidekiq) | 3000; LAN at trigkey:3030 via `optional/dawarich.nix` | `docker-services/services/dawarich.nix` |
| [City-Gifs](https://github.com/blindjoe/city-gifs) | Timelapse GIF gallery, stateless | 3070 | `docker-services/services/city-gifs.nix` |
| [cAdvisor](https://github.com/google/cadvisor) | Container metrics, stateless | 9101 | `docker-services/services/cadvisor.nix` |
| [Cobalt](https://github.com/imputnet/cobalt) | Media download API, stateless | 9000 | `docker-services/services/cobalt.nix` |
| [Rybbit](https://github.com/rybbit-io/rybbit) | Web analytics (+ ClickHouse + Postgres) | 3001 API, 3002 web | `docker-services/services/rybbit.nix` |
| [Endurain](https://codeberg.org/endurain-project/endurain) | Fitness tracking, Garmin sync (+ Postgres + Redis) | 8080 | `docker-services/services/endurain.nix` |

## gmktec

| Service | What | Port | Module | Data |
|---------|------|------|--------|------|
| [restic REST server](backup.md) | Stores trigkey's backups on the T7 | 8000 (trigkey only) | `gmktec/backup-server.nix` | `/mnt/backup/restic` |
| Newt | Pangolin tunnel client | — | `gmktec/newt.nix` | — |
| [MeshLLM](meshllm.md) | Local LLM API, CPU | 9337 API, 3131 console (loopback) | `gmktec/meshllm.nix` | `/var/lib/mesh-llm/` |
| SABnzbd | Download client | 8080 LAN | `gmktec/sabnzbd.nix` | `/data/usenet/` |
| Prowlarr | Indexer manager | 9696 LAN | `gmktec/prowlarr.nix` | `/var/lib/prowlarr/` |
| Sonarr | TV | 8989 LAN | `gmktec/sonarr.nix` | `/var/lib/sonarr/`, `/data/media/tv` |
| Radarr | Film | 7878 LAN | `gmktec/radarr.nix` | `/var/lib/radarr/`, `/data/media/movies` |
| [Jellyfin](../media/jellyfin.md) | `/data` library with VAAPI, server 2 of 2 | 8096 LAN | `gmktec/jellyfin.nix` | `/data/media/`, `/var/lib/jellyfin` |
| Piper | Text to speech | 5000 LAN | `gmktec/piper.nix` | — |
| [Papra](https://github.com/papra-hq/papra) | Documents (SQLite), `papra.local`, not backed up | 1221 LAN | `gmktec/papra.nix` | `/srv/papra/app-data/` |
| media metrics | `du` of `/data` as node-exporter metrics | — | `gmktec/media-metrics.nix` | `/var/lib/node-exporter-textfile` |
| `/data` tree | Shared media root, group `media`, 2775 setgid | — | `gmktec/media-storage.nix` | `/data/` |

Sonarr and Radarr **move** finished downloads into the library (nothing seeds). A move is atomic only within one filesystem, so `/data` must stay one filesystem.

## Both hosts

| Service | What | Port | Module | Data |
|---------|------|------|--------|------|
| [Portless](../networking.md#portless--lan-names) | `*.local` names for LAN services | 80, 1355, UDP 5353 | `optional/portless.nix`, aliases in `inventory.nix` | `/var/lib/portless` |
| node exporter, cAdvisor | Host and container metrics | 9100, 9101 | `optional/monitoring/exporters.nix` | — |
