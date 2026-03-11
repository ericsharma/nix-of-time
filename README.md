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
                  │    City-Gifs                                 │
                  │                                             │
                  │  Native services:                           │
                  │    Immich, Vaultwarden, Garage S3, Newt,     │
                  │    Home Assistant                             │
                  │                                             │
                  │  ┌───────────────────────────────────────┐  │
                  │  │  Incus: docker-services (NixOS LXC)   │  │
                  │  │    Docker containers (oci-containers): │  │
                  │  │      Koito, Karakeep, Dawarich,        │  │
                  │  │      Komodo Periphery                  │  │
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
│   │   └── vaultwarden.nix            # Password manager
│   ├── optional/                      # Opt-in modules (imported per-host as needed)
│   │   └── homeassistant.nix          # Home Assistant + Lovelace dashboard (YAML mode)
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
│   │       └── city-gifs.nix          # City timelapse GIFs
│   └── docker-services/               # NixOS LXC container (runs inside Incus)
│       ├── default.nix                # LXC base config, Docker, SSH
│       ├── sops.nix                   # Container-specific secrets
│       └── services/                  # Docker OCI container definitions
│           ├── koito.nix              # Music dashboard (app + postgres)
│           ├── karakeep.nix           # Bookmark manager (web + meilisearch + chrome)
│           ├── dawarich.nix           # Location tracking (app + sidekiq + postgres + redis)
│           └── periphery.nix          # Komodo Periphery agent
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

## Adding a new machine

Create `hosts/<name>/`, import `../common`, and add the host to `flake.nix`.
