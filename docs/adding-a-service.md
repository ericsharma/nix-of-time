# Adding a service

Fastest path: run `/new-service` in Claude Code, which does every step below. By hand, it takes five steps.

## 1. Pick the tier and file

Choose the tier with [When to use which](architecture.md#when-to-use-which), then:

| Case | File | Imported how |
|------|------|--------------|
| Native or Podman, any host could run it | `hosts/nixos/optional/<name>.nix` | Automatic on trigkey; gmktec must list it |
| Only one host should run it | `hosts/nixos/<host>/<name>.nix` | Add it to that host's `imports` |
| Docker stack | `hosts/nixos/docker-services/services/<name>.nix` | Automatic |

## 2. Write the module

Podman on trigkey or gmktec:

```nix
{ config, ... }:

{
  sops.secrets."<name>/env" = { };

  systemd.tmpfiles.rules = [ "d /srv/<name>/data 0750 root root -" ];

  virtualisation.oci-containers.containers.<name> = {
    image = "docker.io/org/image:<pinned-tag>";
    ports = [ "127.0.0.1:<host-port>:<container-port>" ];
    volumes = [ "/srv/<name>/data:/data" ];
    environmentFiles = [ config.sops.secrets."<name>/env".path ];
  };
}
```

Docker stack in the LXC. Declare the secret in `hosts/nixos/docker-services/sops.nix` as `"docker-services/<name>/env" = { };`, then:

```nix
{ config, ... }:

{
  virtualisation.oci-containers.containers.<name> = {
    image = "docker.io/org/image:<pinned-tag>";
    ports = [ "<host-port>:<container-port>" ];
    volumes = [ "/srv/<name>/data:/data" ];
    environmentFiles = [ config.sops.secrets."docker-services/<name>/env".path ];
  };
}
```

- **Add the secret value:** `sops secrets/secrets.yaml`. Shapes: [Secrets](secrets.md).
- **Pin the image tag.** An unpinned tag turns every rebuild into a silent upgrade.
- **Stateful LXC service:** first add the host data directory and an Incus disk device in `hosts/nixos/trigkey/containers.nix`, and `rebuild` trigkey.

## 3. Decide backup and exposure

- **Backup:** add the data path to a restic job in `hosts/nixos/trigkey/backup.nix` (trigkey and LXC data only; dump databases, don't copy their directories). Otherwise start the module with `# NOT backed up — <reason>`. There is no third option.
- **Exposure:** stay on `127.0.0.1` by default. For public access, add a Pangolin route. For LAN access, add a `*.local` alias in `inventory.nix`. See [Networking](networking.md).

## 4. Build and deploy

```bash
git add hosts/          # the flake ignores untracked files
nix fmt
nix flake check
rebuild                 # or rebuild-docker, or the gmktec command
```

Verify: `systemctl status podman-<name>` (Docker in the LXC: `docker-<name>`), then `curl -sI http://127.0.0.1:<port>`.

## 5. Record it

Add a row to the [service inventory](services/README.md).
