# docker-services

A NixOS LXC in Incus on trigkey, with nested Docker. It exists so multi-container stacks can find each other by name through Docker's built-in DNS.

```bash
rebuild-docker    # deploy; works from trigkey only
```

| | |
|---|---|
| Address | `10.0.100.10` on the `incusbr0` bridge |
| Base image | `images:nixos/25.11`, `security.nesting = true` |
| Config | `hosts/nixos/docker-services/` |
| Launcher | `hosts/nixos/trigkey/containers.nix` |
| Data | `/srv/docker-services/` on trigkey |

## What runs here

| Service | Port | Stack |
|---------|------|-------|
| Koito | 4110 | app + PostgreSQL |
| Karakeep | 3088 | app + Meilisearch + headless Chrome |
| Dawarich | 3000 (LAN: `trigkey:3030`) | Rails + PostGIS + Redis + Sidekiq |
| Rybbit | 3001 API, 3002 web | backend + client + ClickHouse + PostgreSQL |
| Endurain | 8080 | app + PostgreSQL + Redis |
| Cobalt | 9000 | media download API |
| City-Gifs | 3070 | read-only gallery |
| cAdvisor | 9101 | container metrics |

A single container with no sidecar database belongs on Podman on trigkey instead. See [Architecture](../architecture.md#when-to-use-which).

## Adding a stateful service

Deploy trigkey **first**, or the container starts against a directory that doesn't exist.

1. In `hosts/nixos/trigkey/containers.nix`, add the host data directory and the Incus disk device. Run `rebuild`.
2. Add `hosts/nixos/docker-services/services/<svc>.nix`. Run `rebuild-docker`.

## How it works

1. `incus-docker-services.service` on trigkey creates the container with the base image, nesting, the static address, and the disk devices.
2. The container has its own `nixosConfiguration`, deployed with `nixos-rebuild --target-host root@10.0.100.10`.
3. Stacks are `virtualisation.oci-containers` with the Docker backend, auto-imported from `services/`.
4. sops-nix decrypts inside the container with its own SSH host key. Secrets live under `docker-services:` in `secrets/secrets.yaml` and are declared in `hosts/nixos/docker-services/sops.nix`.
5. Data stays on trigkey and is mounted in with UID shifting.

**Recreating the container keeps all data.** To re-bootstrap, mount the config and run `nixos-rebuild switch`.

## Notes

- Sudo needs a password inside the LXC, but `rebuild-docker` connects as `root`, so deploys stay non-interactive.
- `/srv/docker-services` has its own restic job at 04:00. See [Backup and restore](../services/backup.md).
- Pin every image. An unpinned tag turns a rebuild into a silent upgrade.
