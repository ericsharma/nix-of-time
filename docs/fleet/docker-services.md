# docker-services

A NixOS LXC running inside Incus on trigkey, with nested Docker. It exists for
one reason: multi-container stacks need Docker's built-in DNS so containers can
resolve each other by name.

| | |
|---|---|
| Address | `10.0.100.10`, on the `incusbr0` bridge |
| Base image | `images:nixos/25.11`, with `security.nesting = true` |
| Config | `hosts/nixos/docker-services/` |
| Launcher | `hosts/nixos/trigkey/containers.nix` |
| Host data | `/srv/docker-services/` |
| Deploy | `rebuild-docker` |

It is a separate `nixosConfiguration` in the same flake. Editing it has no
effect on trigkey until you deploy it.

## What runs here

| Service | Port | Shape |
|---------|------|-------|
| Koito | 4110 | app + PostgreSQL |
| Karakeep | 3088 | app + Meilisearch + headless Chrome |
| Dawarich | 3000 | Rails + PostGIS + Redis + Sidekiq |
| Rybbit | 3001 API, 3002 web | backend + client + ClickHouse + PostgreSQL |
| Endurain | 8080 | app + PostgreSQL + Redis |
| Cobalt | 9000 | media download API, pinned image |
| City-Gifs | 3070 | read-only, resource-limited |
| cAdvisor | 9101 | container metrics, scraped by Prometheus |

Every one of them is a multi-container stack, or needs the Docker socket. A
single container with no sidecar database belongs on Podman on trigkey
instead. See [Architecture](../architecture.md#when-to-use-which).

Dawarich is reached from the LAN at `trigkey:3030`, through an nginx proxy
declared in `hosts/nixos/optional/dawarich.nix`.

## Lifecycle

1. **Launch.** `incus-docker-services.service` creates the container from the
   base image with nesting on, the static address, and host-backed disk
   devices.
2. **Config.** The container has its own `nixosConfiguration`, deployed with
   `nixos-rebuild --target-host root@10.0.100.10`.
3. **Services.** Stacks are `virtualisation.oci-containers` with the Docker
   backend.
4. **Secrets.** sops-nix decrypts inside the container, with its own age key
   derived from the container's SSH host key. LXC secrets live under a
   `docker-services:` namespace in `secrets/secrets.yaml`.
5. **Persistence.** Data lives on the trigkey host at `/srv/docker-services/`
   and is mounted in through Incus disk devices with UID shifting.

**Deleting and recreating the container preserves all data.** To re-bootstrap,
mount the config and run `nixos-rebuild switch`.

## Adding a stateful service

This is the one change that needs **both** hosts deployed, in order:

1. Add the host-side data directory and the Incus disk mount in
   `hosts/nixos/trigkey/containers.nix`, then run `rebuild`.
2. Add the container in `hosts/nixos/docker-services/services/<svc>.nix`, then
   run `rebuild-docker`.

Doing it the other way round starts the container against a directory that
does not exist yet.

## Operating notes

- **Sudo needs a password here**, unlike trigkey. You reach it as
  `root@10.0.100.10` over SSH, which `rebuild-docker` already does, so the path
  stays non-interactive.
- `/srv/docker-services` is covered by its own restic job. See
  [Backup and restore](../services/backup.md).
- Pin container images. Cobalt is pinned for a reason — an unpinned tag turns a
  rebuild into a silent upgrade.
