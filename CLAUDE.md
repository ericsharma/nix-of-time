# CLAUDE.md

Conventions specific to this repo. See `docs/` for depth.

## Where services live

- `hosts/optional/<svc>.nix` — shared library of opt-in service modules (native NixOS *and* Podman). Machine-agnostic; future hosts pick from here.
- `hosts/docker-services/services/<svc>.nix` — multi-container Docker stacks running inside the Incus LXC.
- `hosts/trigkey/` — only things tied to this physical box: hardware, networking, the Incus LXC launcher (`containers.nix`), storage-coupled services (Immich, Garage).

Pick the tier:
- Native NixOS module exists in nixpkgs → use it (in `hosts/optional/`).
- Single container, no sidecar DB → Podman in `hosts/optional/`.
- Multi-container needing inter-container DNS → Docker stack in `hosts/docker-services/services/`.

## Two independent systems, one flake

`trigkey` and `docker-services` are separate `nixosConfigurations`. Editing one has zero effect on the other until you deploy.

| Touched | Run |
|---------|-----|
| `hosts/trigkey/`, `hosts/optional/`, `hosts/common/` | `rebuild` |
| `hosts/docker-services/` | `rebuild-docker` |
| New stateful docker-services service | both — add host dir + Incus disk mount in `hosts/trigkey/containers.nix`, then add the container in `hosts/docker-services/services/` |

## sops

One file `secrets/secrets.yaml`, decrypted independently by each system (each has its own age key from its SSH host key). LXC secrets live under a `docker-services:` namespace.

Two shapes:
- **Env block** for `environmentFile` consumers — `service.env: |` then `KEY=value` lines.
- **Scalar** for path-to-single-secret consumers — `service.<name>: <value>`.

Declare in the module: `sops.secrets."service/env" = {};` (or `"service/<name>"`).

## Networking

Services bind to `127.0.0.1`. Public exposure goes through Newt → Pangolin (zero open ports). Open a firewall port only when LAN access is genuinely needed.

## Commits

Conventional commits, lowercase prefix: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`. Subject-only is fine; add a body when *why* matters.
