# Architecture

## Deployment strategies

Two strategies are used, chosen based on service complexity:

**Podman** — single-container services run directly on the trigkey host via `virtualisation.oci-containers` with the Podman backend. Good for standalone apps with no inter-container networking needs.

**Incus + NixOS LXC** — multi-container stacks run inside a NixOS LXC container (`docker-services`) with nested Docker, managed via `virtualisation.oci-containers` with a Docker backend. Docker's built-in DNS gives containers automatic name resolution within the LXC.

### When to use which

| Criteria | Podman (trigkey) | Docker (docker-services) |
|----------|-----------------|--------------------------|
| Single container, no sidecar DBs | Preferred | Works |
| Multi-container stack (app + DB + worker) | Avoid | Preferred |
| Needs inter-container DNS | No | Yes |
| Native NixOS module available | Use the module directly | N/A |
| Needs Docker socket access | No | Yes |

## Docker-services container lifecycle

The `docker-services` container is a NixOS LXC running inside Incus with nested Docker:

1. **Launch** — `incus-docker-services.service` creates the container from `images:nixos/25.11` with `security.nesting=true`, static IP (`10.0.100.10`), and host-backed disk devices
2. **Config** — The container has its own `nixosConfiguration` in the flake, deployed via `nixos-rebuild --target-host`
3. **Services** — Multi-container stacks are defined as `virtualisation.oci-containers` with Docker backend, getting Docker's built-in DNS for inter-container resolution
4. **Secrets** — sops-nix decrypts secrets inside the container using its own age key (derived from the container's SSH host key)
5. **Persistence** — Data lives on the NixOS host at `/srv/docker-services/` and is mounted into the container via Incus disk devices with UID shifting

Deleting and recreating the container preserves all data. Re-bootstrap by mounting the config and running `nixos-rebuild switch`.

## Networking

- Trigkey host uses DHCP on `enp1s0`
- Incus bridge (`incusbr0`) provides networking for the LXC container
- `docker-services` gets a static IP of `10.0.100.10`
- nftables rules handle forwarding between the bridge and host
- Most services bind to `localhost` and are exposed externally via Newt (Pangolin tunnel)
