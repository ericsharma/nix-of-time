# nixos-config

Flake-based NixOS configuration for a self-hosted homelab running on a Trigkey mini PC (32GB RAM, 512GB SSD).

## Architecture

All services are declaratively configured, secrets are encrypted with [sops-nix](https://github.com/Mic92/sops-nix), and data is persisted on the host filesystem for durability across container recreation.

**Two deployment strategies:**

- **Podman** — single-container services run directly on the trigkey host via `virtualisation.oci-containers`
- **Incus + NixOS LXC** — multi-container stacks run inside a NixOS LXC container (`docker-services`) with nested Docker, managed via `virtualisation.oci-containers` with a Docker backend

```
                  ┌─────────────────────────────────────────────┐
                  │              NixOS (trigkey)                 │
                  │                                             │
                  │  Podman containers:                         │
                  │    Komodo Core, Strava, Kavita, Memos,      │
                  │    Multi-Scrobbler, Networking Tools,        │
                  │    City-Gifs, WhisperX Transcription         │
                  │                                             │
                  │  Native services:                           │
                  │    Immich, Vaultwarden, Garage S3, Newt,     │
                  │    Home Assistant, Prometheus, Grafana,       │
                  │    Syncthing                                  │
                  │                                             │
                  │  ┌───────────────────────────────────────┐  │
                  │  │  Incus: docker-services (NixOS LXC)   │  │
                  │  │    Docker containers (oci-containers): │  │
                  │  │      Koito, Karakeep, Dawarich,        │  │
                  │  │      Komodo Periphery, cAdvisor         │  │
                  │  │                                        │  │
                  │  │    Own sops-nix secrets (age key from  │  │
                  │  │    container SSH host key)             │  │
                  │  │                                        │  │
                  │  │    Data mounted from NixOS host:       │  │
                  │  │      /srv/docker-services/* → /srv/*   │  │
                  │  └───────────────────────────────────────┘  │
                  └─────────────────────────────────────────────┘
```

## Directory structure

```
nixos-config/
├── flake.nix                          # Inputs: nixpkgs, sops-nix, home-manager
├── secrets/
│   └── secrets.yaml                   # sops-encrypted secrets (age)
├── home/
│   ├── common/                        # Shared home-manager config
│   │   ├── default.nix                # Entry point
│   │   ├── packages.nix               # User packages (nodejs, ripgrep, etc.)
│   │   ├── git.nix                    # Git config and aliases
│   │   └── shell.nix                  # Bash aliases, bat, direnv
│   └── trigkey/
│       └── default.nix                # Host-specific home overrides
├── hosts/
│   ├── common/                        # Shared system config
│   │   ├── default.nix                # Users, SSH, timezone, packages
│   │   ├── sops.nix                   # Secret definitions (trigkey)
│   │   ├── incus.nix                  # Incus + nftables + bridge networking
│   │   ├── podman.nix                 # Podman + Docker compat
│   │   ├── vaultwarden.nix            # Password manager
│   │   └── monitoring/
│   │       └── exporters.nix          # node_exporter + cAdvisor
│   ├── optional/                      # Opt-in modules (imported per-host as needed)
│   │   ├── homeassistant.nix          # Home Assistant + Lovelace dashboard (YAML mode)
│   │   ├── monitoring.nix             # Prometheus, Grafana, provisioned dashboards
│   │   └── syncthing.nix             # Syncthing file sync (Obsidian vault backup)
│   ├── trigkey/                       # Trigkey mini PC
│   │   ├── default.nix                # Boot, networking, service imports
│   │   ├── hardware-configuration.nix # Auto-generated hardware config
│   │   ├── containers.nix             # Incus container lifecycle (static IP, disk devices)
│   │   ├── immich.nix                 # Photo management
│   │   ├── newt.nix                   # Pangolin tunnel client
│   │   ├── garage.nix                 # S3-compatible object storage
│   │   ├── garage-webui.nix           # Garage admin UI
│   │   ├── backup.nix                 # Restic backups (WIP)
│   │   └── services/                  # Podman OCI container definitions
│   │       ├── komodo.nix             # Container management (Core + MongoDB)
│   │       ├── strava.nix             # Strava activity statistics
│   │       ├── kavita.nix             # Book/manga reader
│   │       ├── memos.nix              # Note-taking
│   │       ├── scrobbler.nix          # Music scrobbling
│   │       ├── networking-tools.nix   # Network diagnostics
│   │       ├── city-gifs.nix          # City timelapse GIFs
│   │       └── whisper-transcription.nix # Audio transcription + diarization
│   └── docker-services/               # NixOS LXC container (runs inside Incus)
│       ├── default.nix                # LXC base config, Docker, SSH
│       ├── sops.nix                   # Container-specific secrets
│       └── services/                  # Docker OCI container definitions
│           ├── koito.nix              # Music dashboard (app + postgres)
│           ├── karakeep.nix           # Bookmark manager (web + meilisearch + chrome)
│           ├── dawarich.nix           # Location tracking (app + sidekiq + postgres + redis)
│           ├── periphery.nix          # Komodo Periphery agent
│           └── cadvisor.nix           # Container metrics exporter for Prometheus
```

## Secrets management

All secrets are in `secrets/secrets.yaml`, encrypted with [age](https://github.com/FiloSottile/age) via sops-nix. Each host decrypts using its own SSH ed25519 key at `/etc/ssh/ssh_host_ed25519_key`.

Both the trigkey host and the docker-services container are sops recipients — the container has its own SSH host key converted to an age key, so it decrypts its own secrets natively via sops-nix.

```bash
# Edit secrets
sops secrets/secrets.yaml

# Add a new secret: define it in the relevant sops.nix, then add the value in sops
```

## Docker-services container lifecycle

The `docker-services` container is a NixOS LXC running inside Incus with nested Docker:

1. **Launch** — `incus-docker-services.service` creates the container from `images:nixos/25.11` with `security.nesting=true`, static IP (`10.0.100.10`), and host-backed disk devices
2. **Config** — The container has its own `nixosConfiguration` in the flake, deployed via `nixos-rebuild --target-host`
3. **Services** — Multi-container stacks are defined as `virtualisation.oci-containers` with Docker backend, getting Docker's built-in DNS for inter-container resolution
4. **Secrets** — sops-nix decrypts secrets inside the container using its own age key
5. **Persistence** — Data lives on the NixOS host at `/srv/docker-services/` and is mounted into the container via Incus disk devices with UID shifting

Deleting and recreating the container preserves all data. Re-bootstrap by mounting the config and running `nixos-rebuild switch`.

## Applying changes

```bash
# Rebuild trigkey (aliased)
rebuild                  # sudo nixos-rebuild switch --flake ~/nixos-config#$(hostname)

# Deploy to docker-services container (aliased)
rebuild-docker           # nixos-rebuild switch --flake ~/nixos-config#docker-services --target-host root@10.0.100.10

# Test without making it the boot default
sudo nixos-rebuild test --flake .#trigkey
```

## Monitoring

Prometheus and Grafana run on trigkey (`hosts/optional/monitoring.nix`). Node exporter runs on every host (`hosts/common/monitoring/exporters.nix`), and cAdvisor runs inside the docker-services LXC container (`hosts/docker-services/services/cadvisor.nix`) to get Docker container metrics with proper name/image labels.

- **Prometheus** — `http://trigkey:9090`, 30d retention, scrapes node_exporter (port 9100) and cAdvisor (port 9101) on all nodes
- **Grafana** — `http://trigkey:3000`, admin password from sops (`grafana/env`), Prometheus datasource auto-provisioned
- **Dashboards** — fetched from grafana.com at build time, datasource variables patched automatically

To add a new scrape target, add the host to the `nodes` attrset in `monitoring.nix`.

### Dashboards

**Node Exporter Full** (Grafana ID 1860) — provisioned via `monitoring.nix`
- Data source: `node_exporter` running on each host (port 9100)
- Purpose: hardware and OS-level metrics for each machine
- Panels: CPU usage per core, memory/swap usage, disk I/O and space, network traffic, system load, systemd service states, filesystem usage, and hardware temperatures
- Use the `instance` dropdown at the top to switch between hosts (trigkey, docker-services)

**Docker monitoring** — built into Grafana via cAdvisor metrics
- Data source: cAdvisor running inside the docker-services LXC (port 9101)
- Purpose: per-container resource usage for all Docker containers
- Panels: CPU usage, memory consumption, network I/O, and disk reads/writes per named container
- Only covers containers inside `docker-services` — Podman containers on trigkey are not instrumented with Docker-level labels

## Audio transcription

Automated watched-folder transcription using [WhisperX](https://github.com/m-bain/whisperX) (`hosts/trigkey/services/whisper-transcription.nix`). Integrated with Syncthing and Obsidian for a seamless end-to-end workflow: drop an audio file into your Obsidian vault on any device, and a diarized, timestamped transcript appears next to it.

- **Container** — `ghcr.io/jim60105/whisperx:no_model`, CPU-only (INT8), invoked per-file via `podman run`
- **Watcher** — systemd service using `inotifywait` monitors vault `Transcriptions/` folders, starts on boot
- **Diarization** — HuggingFace token loaded via sops `EnvironmentFile` for pyannote speaker models
- **Output** — Obsidian markdown with `![[audio.m4a]]` embed, timestamps, and speaker labels
- **Filtering** — only processes audio files (`m4a`, `mp3`, `wav`, `ogg`, `flac`, etc.), skips files that already have a matching transcript

### Workflow

```
Laptop (Obsidian)                    Trigkey (headless)
┌────────────────────┐               ┌────────────────────────────┐
│ Drop audio into    │   Syncthing   │ inotifywait detects file   │
│ Transcriptions/    │──────────────►│ whisperx transcribes       │
│                    │               │ .md appears alongside audio│
│ Transcript + audio │◄──────────────│ Syncthing syncs back       │
│ appear in Obsidian │               │                            │
└────────────────────┘               └────────────────────────────┘
```

1. Drop an audio file into the `Transcriptions/` folder in your Obsidian vault
2. Syncthing syncs it to trigkey (`/srv/obsidian/<vault>/Transcriptions/`)
3. inotifywait triggers whisperx (CPU, INT8, speaker diarization)
4. A markdown transcript with an embedded audio player is written next to the audio file
5. Syncthing syncs the transcript back to your laptop
6. Open the transcript in Obsidian — play the audio inline while reading

### Vault routing

Two Obsidian vaults are watched, each with its own `Transcriptions/` folder:

```
/srv/obsidian/Work/Transcriptions/
/srv/obsidian/Brain 2.0/Transcriptions/
```

Drop audio into the `Transcriptions/` folder of whichever vault it belongs to.

## Syncthing

Syncthing (`hosts/optional/syncthing.nix`) provides bidirectional file sync between trigkey and personal devices. Serves as both a backup for Obsidian vaults and the transport layer for the transcription workflow.

- **Web UI** — `http://trigkey:8384`
- **Sync ports** — 22000/tcp+udp (auto-opened)
- **Vaults** — `/srv/obsidian/Work`, `/srv/obsidian/Brain 2.0`

Each vault is configured as a separate Syncthing shared folder, paired with the corresponding vault directory on the laptop. New files (including transcriptions) sync to all paired devices within seconds.

## Adding a new machine

Create `hosts/<name>/`, import `../common`, and add the host to `flake.nix`.
