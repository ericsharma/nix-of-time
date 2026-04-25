# Adding a new service

## 1. Choose a deployment strategy

| Criteria | Podman (trigkey) | Docker (docker-services) |
|----------|-----------------|--------------------------|
| Single container, no sidecar DBs | Preferred | Works |
| Multi-container stack (app + DB + worker) | Avoid | Preferred |
| Needs inter-container DNS | No | Yes |
| Native NixOS module available | Use the module directly | N/A |

See [architecture.md](architecture.md) for more detail.

## 2. Create the service file

### Podman service on trigkey

Create `hosts/optional/<name>.nix` (`hosts/optional/` is the shared library of
opt-in service modules — native NixOS and Podman alike — so the same module
can be reused on a future host by importing it from there):

```nix
{ config, ... }:

{
  virtualisation.oci-containers.containers.<name> = {
    image = "docker.io/org/image:latest";
    ports = [ "127.0.0.1:<host-port>:<container-port>" ];
    volumes = [
      "/srv/<name>/data:/data"
    ];
    environmentFiles = [
      config.sops.secrets."<name>/env".path
    ];
  };
}
```

### Docker service in docker-services LXC

Create `hosts/docker-services/services/<name>.nix`:

```nix
{ config, ... }:

{
  virtualisation.oci-containers.containers.<name> = {
    image = "docker.io/org/image:latest";
    ports = [ "<host-port>:<container-port>" ];
    volumes = [
      "/srv/<name>/data:/data"
    ];
    environmentFiles = [
      config.sops.secrets."docker-services/<name>/env".path
    ];
  };
}
```

## 3. Add secrets

If the service needs secrets (API keys, passwords, env files):

**For trigkey services:**

1. Add the secret definition to `hosts/common/sops.nix`:
   ```nix
   "<name>/env" = {};
   ```

2. Add the value via sops:
   ```bash
   sops secrets/secrets.yaml
   ```

**For docker-services:**

1. Add the secret definition to `hosts/docker-services/sops.nix`:
   ```nix
   "docker-services/<name>/env" = {};
   ```

2. Add the value via sops:
   ```bash
   sops secrets/secrets.yaml
   ```

## 4. Create data directories

For services that persist data, create the host directory:

```bash
# Trigkey service
sudo mkdir -p /srv/<name>/data

# Docker-services (data lives on trigkey host, mounted into LXC)
sudo mkdir -p /srv/docker-services/<name>/data
```

For docker-services, also add an Incus disk device in `hosts/trigkey/containers.nix` to mount the host path into the LXC.

## 5. Import the module

Add the import to the host's `default.nix`:

```nix
# hosts/trigkey/default.nix
imports = [
  # ...
  ../optional/<name>.nix
];

# OR hosts/docker-services/default.nix
imports = [
  # ...
  ./services/<name>.nix
];
```

## 6. Open firewall ports (if needed)

Most services bind to `localhost` and are exposed via Newt. If the service needs direct access, add the port to the host's firewall:

```nix
# In hosts/trigkey/default.nix
networking.firewall.allowedTCPPorts = [ 22 <port> ];
```

## 7. Rebuild

```bash
# Trigkey service
rebuild

# Docker-services
rebuild-docker
```

## 8. Update documentation

Add the service to the inventory table in `docs/services/README.md`.
