# Architecture

One flake builds three NixOS systems. Each deploys on its own, so a change to one does nothing to the others until you deploy it.

| Host | Address | What it is | Deploy |
|------|---------|------------|--------|
| `trigkey` | 192.168.0.202 | Trigkey mini PC. Most services. | `rebuild` |
| `docker-services` | 10.0.100.10 | NixOS LXC in Incus on trigkey. Docker stacks. | `rebuild-docker` |
| `gmktec` | 192.168.0.51 | GMKtec mini PC. Backup target, media library, inference. | `nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo` |

The same flake also builds `m1-mini`, a nix-darwin host in `hosts/darwin/`.

## The import rule

- trigkey imports every file in `hosts/nixos/optional/` with `lib.filesystem.listFilesRecursive`.
- Those modules have no enable flags. Importing one starts its service.
- Every other host lists its imports by name. Copy `hosts/nixos/gmktec/default.nix`, never trigkey's.
- A service meant for one host only goes in that host's directory, not `optional/`. Example: `hosts/nixos/gmktec/papra.nix`.

## When to use which

Check in order. Take the first match.

1. **A native NixOS module exists** → use it, in `hosts/nixos/optional/`.
2. **One container, no sidecar database** → Podman through `virtualisation.oci-containers`, in `hosts/nixos/optional/`.
3. **App + database + worker, needs container-name DNS or the Docker socket** → Docker in the LXC, in `hosts/nixos/docker-services/services/`.

Why the LXC exists: Docker's built-in DNS lets the containers in a stack find each other by name. Podman on the host is simpler for everything else.

A stateful tier-3 service needs trigkey deployed first. See [docker-services](fleet/docker-services.md#adding-a-stateful-service).

## More

- Firewall, Pangolin, `*.local` names: [Networking](networking.md)
- LXC lifecycle and persistence: [docker-services](fleet/docker-services.md)
- A new host: [Adding a machine](adding-a-machine.md)
