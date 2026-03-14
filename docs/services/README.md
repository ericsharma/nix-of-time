# Service inventory

## Trigkey host — Native services

| Service | Port | Config | Data path |
|---------|------|--------|-----------|
| [Immich](https://immich.app/) (photos) | 2283 | `hosts/trigkey/immich.nix` | `/mnt/immich-data/immich` |
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (passwords) | 8222 | `hosts/common/vaultwarden.nix` | — |
| [Garage S3](https://garagehq.deuxfleurs.fr/) (object storage) | 3900 (S3), 3901 (RPC) | `hosts/trigkey/garage.nix` | `/var/lib/garage/` |
| Garage WebUI | 3909 | `hosts/trigkey/garage-webui.nix` | — |
| [Newt](https://docs.pangolin.dev/) (tunnel client) | — | `hosts/trigkey/newt.nix` | — |
| [Home Assistant](https://www.home-assistant.io/) | 8123 | `hosts/optional/homeassistant.nix` | `/var/lib/hass` |
| [Prometheus](https://prometheus.io/) | 9090 | `hosts/optional/monitoring.nix` | — |
| [Grafana](https://grafana.com/) | 3000 | `hosts/optional/monitoring.nix` | — |
| [Syncthing](https://syncthing.net/) | 8384 (UI), 22000 | `hosts/optional/syncthing.nix` | `/srv/obsidian/` |

## Trigkey host — Podman containers

| Service | Port | Config | Data path |
|---------|------|--------|-----------|
| [Komodo](https://komo.do/) (container mgmt) | 9120 | `hosts/trigkey/services/komodo.nix` | `/srv/komodo/` |
| [Strava Statistics](https://github.com/robiningelbrecht/strava-statistics) | 7080 | `hosts/trigkey/services/strava.nix` | `/srv/strava/` |
| [Kavita](https://www.kavitareader.com/) (books/manga) | 5000 | `hosts/trigkey/services/kavita.nix` | `/srv/kavita/` |
| [Memos](https://www.usememos.com/) (notes) | 5230 | `hosts/trigkey/services/memos.nix` | `/srv/memos` |
| [Multi-Scrobbler](https://github.com/FoxxMD/multi-scrobbler) | 9078 | `hosts/trigkey/services/scrobbler.nix` | `/srv/multi-scrobbler/` |
| [Networking Tools](https://github.com/Lissy93/networking-toolbox) | 3069 | `hosts/trigkey/services/networking-tools.nix` | — |
| [Termix](https://github.com/LukeGus/Termix) | 8080 | `hosts/trigkey/services/termix.nix` | `/srv/termix/` |
| WhisperX (transcription) | — | `hosts/trigkey/services/whisper-transcription.nix` | `/srv/transcription/` |

For details on transcription, see [transcription.md](transcription.md).

## Docker-services LXC — Docker containers

All containers run inside the `docker-services` NixOS LXC at `10.0.100.10`. Data on the host lives under `/srv/docker-services/` and is mounted into the container.

| Service | Port | Config | Data path (host) |
|---------|------|--------|-------------------|
| [Koito](https://github.com/gabehf/koito) (music dashboard) | 4110 | `hosts/docker-services/services/koito.nix` | `/srv/docker-services/koito/` |
| [Karakeep](https://github.com/karakeep-app/karakeep) (bookmarks) | 3088 | `hosts/docker-services/services/karakeep.nix` | `/srv/docker-services/karakeep/` |
| [Dawarich](https://github.com/Freika/dawarich) (location tracking) | 3000 | `hosts/docker-services/services/dawarich.nix` | `/srv/docker-services/dawarich/` |
| [City-Gifs](https://github.com/blindjoe/city-gifs) (timelapse GIFs) | 3070 | `hosts/docker-services/services/city-gifs.nix` | — |
| Komodo Periphery (agent) | 8120 | `hosts/docker-services/services/periphery.nix` | — |
| [cAdvisor](https://github.com/google/cadvisor) (container metrics) | 9101 | `hosts/docker-services/services/cadvisor.nix` | — |

For details on monitoring, see [monitoring.md](monitoring.md).
