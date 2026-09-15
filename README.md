# Nix of Time

NixOS configuration for a self-hosted homelab: two mini PCs, one LXC, ~35 services, fully declarative.

![NixOS 25.11](https://img.shields.io/badge/NixOS-25.11-5277C3?logo=nixos&logoColor=white)

## Deploy

| Host | Run |
|------|-----|
| trigkey | `rebuild` |
| docker-services | `rebuild-docker` (from trigkey only) |
| gmktec | `nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo` |

Try a change on trigkey without changing the boot default: `sudo nixos-rebuild test --flake .#trigkey`

Each host is its own flake output. A change reaches a host only when you deploy that host.

## Machines

| Host | Address | Hardware | Role |
|------|---------|----------|------|
| trigkey | 192.168.0.202 | AMD, 32 GB, 512 GB NVMe + external drive, ~15 W idle | Most services; runs the LXC |
| docker-services | 10.0.100.10 | NixOS LXC inside Incus on trigkey | Multi-container Docker stacks |
| gmktec | 192.168.0.51 | Ryzen 7 5825U, 32 GB + 14 GB zram, 1 TB NVMe, 931 GB T7 SSD | Backup target, media library, local inference |
| m1-mini | — | Mac mini, nix-darwin | macOS host in the same flake |

Per-host pages: [trigkey](docs/fleet/trigkey.md) · [gmktec](docs/fleet/gmktec.md) · [docker-services](docs/fleet/docker-services.md)

## Services

| Area | Services |
|------|----------|
| Photos, media, storage | Immich · Jellyfin (two servers) · Garage S3 · City-Gifs · Cobalt |
| Streaming | EternaTV: Icecast + Liquidsoap radio, HLS video channels |
| Reading, music | Kavita · Multi-Scrobbler · Koito |
| Fitness, location | Dreeve · Endurain · Dawarich |
| Home | Home Assistant · AirGradient ONE |
| AI, automation | WhisperX · MeshLLM · Hermes Agent · Syncthing · PiroueSync |
| Notes, documents | Memos · Karakeep · Vaultwarden · Papra |
| Infrastructure | Prometheus · Grafana · Newt · Tailscale · Portless · Ladder · TapMap · Termix · Networking Tools · Rybbit · PGWeb |
| Sites | ericsharma.xyz · Belle Watson Studios · Options Ledger · docs.ericsharma.xyz |

Ports, modules, and data paths: [service inventory](docs/services/README.md).

## Where things run

| Tier | Use when | Lives in |
|------|----------|----------|
| Native NixOS module | A module exists | `hosts/nixos/optional/` |
| Podman | One container, no sidecar database | `hosts/nixos/optional/` |
| Docker in the LXC | App + database + worker that need container-name DNS | `hosts/nixos/docker-services/services/` |

Full rules: [Architecture](docs/architecture.md#when-to-use-which).

## Repo layout

| Path | Holds |
|------|-------|
| `hosts/nixos/common/` | Shared system config: users, SSH, sops, Podman, Incus |
| `hosts/nixos/optional/` | Opt-in service modules, imported per host |
| `hosts/nixos/<host>/` | One host: boot, hardware, host-only services |
| `hosts/nixos/docker-services/services/` | Docker stacks for the LXC |
| `hosts/darwin/` | nix-darwin hosts (`m1-mini`) |
| `home/{common,optional,<host>}/` | home-manager config |
| `inventory.nix` | Cross-host facts: addresses, `*.local` aliases |
| `secrets/` | sops-encrypted secrets |

## Docs

Browse them at **[docs.ericsharma.xyz](https://docs.ericsharma.xyz)**, or here:

- **Start:** [Architecture](docs/architecture.md) · [Networking](docs/networking.md) · [Secrets](docs/secrets.md) · [Service inventory](docs/services/README.md)
- **Do:** [Add a service](docs/adding-a-service.md) · [Add a machine](docs/adding-a-machine.md) · [Backup and restore](docs/services/backup.md) · [Claude Code skills](docs/claude-skills.md)
- **Media:** [Overview](docs/media/README.md) · [Garage](docs/media/garage.md) · [Guitar library](docs/media/guitar-library.md) · [Jellyfin](docs/media/jellyfin.md) · [EternaTV](docs/media/eternatv.md)
- **Services:** [Monitoring](docs/services/monitoring.md) · [MeshLLM](docs/services/meshllm.md) · [Ladder](docs/services/ladder.md) · [Transcription](docs/services/transcription.md) · [Syncthing](docs/services/syncthing.md)

## Documentation site

`docs-site/` builds an [Astro Starlight](https://starlight.astro.build/) site from `docs/`. nginx serves it on `127.0.0.1:4209`, and Pangolin publishes it at `docs.ericsharma.xyz`. Module: `hosts/nixos/optional/docs-site.nix`.

```bash
cd docs-site
corepack pnpm install
corepack pnpm run dev      # http://localhost:4321
corepack pnpm run build    # what the Nix derivation runs
```

- Write plain GitHub markdown in `docs/`. `docs-site/scripts/sync-docs.mjs` adds frontmatter and rewrites `.md` links at build time.
- The first paragraph under a page's `# Title` becomes its site description.
- A new page appears in the sidebar only after you add it to `sidebar` in `docs-site/astro.config.mjs`. Pages in `docs/services/` are added automatically.
