# nixos-config

Flake-based NixOS configuration for a self-hosted homelab running on a Trigkey mini PC (32GB RAM, 512GB SSD).

All services are declaratively configured, secrets are encrypted with [sops-nix](https://github.com/Mic92/sops-nix), and data is persisted on the host filesystem for durability across container recreation.

## Architecture

```
                  ┌─────────────────────────────────────────────┐
                  │              NixOS (trigkey)                 │
                  │                                             │
                  │  Podman containers:                         │
                  │    Komodo, Strava, Kavita, Memos,           │
                  │    Multi-Scrobbler, Networking Tools,        │
                  │    Termix, WhisperX Transcription            │
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
                  │  │      City-Gifs, Komodo Periphery,      │  │
                  │  │      cAdvisor                           │  │
                  │  └───────────────────────────────────────┘  │
                  └─────────────────────────────────────────────┘
```

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
| Service inventory | [docs/services/](docs/services/README.md) |
| Monitoring (Prometheus, Grafana) | [docs/services/monitoring.md](docs/services/monitoring.md) |
| Audio transcription (WhisperX) | [docs/services/transcription.md](docs/services/transcription.md) |
| Syncthing file sync | [docs/services/syncthing.md](docs/services/syncthing.md) |
| Adding a new service | [docs/adding-a-service.md](docs/adding-a-service.md) |
| Adding a new machine | [docs/adding-a-machine.md](docs/adding-a-machine.md) |
