# nixos-config

Flake-based NixOS configuration for a self-hosted homelab running on a Trigkey mini PC (32GB RAM, 512GB SSD).

## Architecture

All services are declaratively configured, secrets are encrypted with [sops-nix](https://github.com/Mic92/sops-nix), and data is persisted on the host filesystem for durability across container recreation.

**Two container strategies are used:**

- **Podman** — single-container services run directly on the host via `virtualisation.oci-containers`
- **Incus** — multi-container stacks (Docker Compose) run inside an Alpine Linux container with nested Docker, provisioned automatically via cloud-init and systemd

```
                  ┌─────────────────────────────────────────────┐
                  │              NixOS (trigkey)                 │
                  │                                             │
                  │  Podman containers:                         │
                  │    Komodo Core, Strava, Kavita, Memos,      │
                  │    Multi-Scrobbler, Networking Tools         │
                  │                                             │
                  │  Native services:                           │
                  │    Immich, Vaultwarden, Garage S3, Newt      │
                  │                                             │
                  │  ┌───────────────────────────────────────┐  │
                  │  │  Incus: docker-services (Alpine)      │  │
                  │  │    Docker Compose stacks:              │  │
                  │  │      Koito, Karakeep, Dawarich,        │  │
                  │  │      Komodo Periphery                  │  │
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
│   │   ├── sops.nix                   # Secret definitions
│   │   ├── incus.nix                  # Incus + nftables + bridge networking
│   │   ├── podman.nix                 # Podman + Docker compat
│   │   └── vaultwarden.nix            # Password manager
│   └── trigkey/                       # Trigkey mini PC
│       ├── default.nix                # Boot, networking, service imports
│       ├── hardware-configuration.nix # Auto-generated hardware config
│       ├── containers.nix             # Incus container lifecycle + provisioning
│       ├── immich.nix                 # Photo management
│       ├── newt.nix                   # Pangolin tunnel client
│       ├── garage.nix                 # S3-compatible object storage
│       ├── garage-webui.nix           # Garage admin UI
│       ├── backup.nix                 # Restic backups (WIP)
│       ├── cloud-init/
│       │   └── docker-services.yaml   # Alpine container bootstrap
│       ├── compose/                   # Docker Compose stacks (pushed into Incus)
│       │   ├── koito/
│       │   ├── karakeep/
│       │   ├── dawarich/
│       │   └── periphery/
│       └── services/                  # Podman OCI container definitions
│           ├── komodo.nix             # Container management (Core + MongoDB)
│           ├── strava.nix             # Strava activity statistics
│           ├── kavita.nix             # Book/manga reader
│           ├── memos.nix              # Note-taking
│           ├── scrobbler.nix          # Music scrobbling
│           └── networking-tools.nix   # Network diagnostics
```

## Secrets management

All secrets are in `secrets/secrets.yaml`, encrypted with [age](https://github.com/FiloSottile/age) via sops-nix. Decryption uses each host's SSH ed25519 key at `/etc/ssh/ssh_host_ed25519_key`.

```bash
# Edit secrets
sops secrets/secrets.yaml

# Add a new secret: define it in hosts/common/sops.nix, then add the value in sops
```

Secrets for the docker-services Incus container are decrypted on the NixOS host and pushed into the container as `.env` files by the provisioning service.

## Incus container lifecycle

The `docker-services` container is fully declarative:

1. **Launch** — `incus-docker-services.service` creates the container with `security.nesting=true`, static IP, and host-backed disk devices
2. **Bootstrap** — cloud-init installs Docker, creates an OpenRC service for compose stacks
3. **Provision** — `docker-services-provision.service` waits for cloud-init, pushes compose files and sops-decrypted `.env` files, then starts the stacks
4. **Persistence** — data lives on the NixOS host at `/srv/docker-services/` and is mounted into the container via Incus disk devices with UID shifting

Deleting and recreating the container preserves all data.

## Applying changes

```bash
sudo nixos-rebuild switch --flake .#trigkey
```

To test without making it the boot default:

```bash
sudo nixos-rebuild test --flake .#trigkey
```

## Adding a new machine

Create `hosts/<name>/`, import `../common`, and add the host to `flake.nix`.
