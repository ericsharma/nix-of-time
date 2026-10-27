# Pangolin nodes

The public edge: two RackNerd VPSs for the [Pangolin](../services/pangolin.md) stack. Not on the LAN. Only node 1 runs the stack until the cluster (Enterprise Edition + PostgreSQL + Redis); then each public name gets a second A record for node 2.

```bash
nixos-rebuild switch --flake .#racknerd-pangolin --target-host root@172.245.86.223   # node 1, from trigkey
nixos-rebuild switch --flake .#racknerd --target-host root@198.46.199.125            # node 2
etd-ssh racknerd-pangolin '<command>'                                                # a shell command, no ssh key needed
```

| | racknerd-pangolin (node 1) | racknerd (node 2) |
|---|---|---|
| Address | `172.245.86.223`; every public A record | `198.46.199.125` |
| Runs | Pangolin + Gerbil + Traefik, etd | etd only |
| Config | `hosts/nixos/racknerd-pangolin/` | `hosts/nixos/racknerd/` |

Both: KVM, 1 vCPU, BIOS boot, 957 MB + zram + 1 GB swap partition, 20 GB virtio `/dev/vda`. Shared base: `hosts/nixos/pangolin-node/`, home: `home/pangolin-node/`, secrets: `secrets/pangolin.yaml` only.

## What runs

| Service | Port | Purpose |
|---------|------|---------|
| [Pangolin](../services/pangolin.md) + Gerbil + Traefik (node 1) | 80, 443 (TCP+UDP), 5432, 51820/udp, 21820/udp | Reverse proxy and tunnels for every public service |
| etd + manymux node | — | E.T. app and `etd-ssh` reach the box |

## How they differ from the other hosts

- **Own sops file.** Their age keys open `secrets/pangolin.yaml` and nothing else. Never add a node to the `secrets.yaml` rule in `.sops.yaml`: these hosts face the internet.
- **Root login by key, from trigkey only.** Deploys run as root. `eric` keeps a sudo password, because every etd network member can run commands as `eric`.
- **No `listFilesRecursive` of `optional/`.** Imports are explicit, as on gmktec.

## Reinstall

nixos-anywhere does **not** work here: its kexec step is OOM-killed on 957 MB. NixOS went on over RackNerd's Ubuntu image in place (`NIXOS_LUSTRATE`), as nixos-infect does, but with this flake's closure:

1. RackNerd panel: reinstall Ubuntu 22.04. Copy trigkey's key to root.
2. On the VPS, as root: make the `nixbld` group and users, then `curl -L https://nixos.org/nix/install | sh -s -- --no-channel-add --no-daemon`.
3. Update the UUIDs in `hardware-configuration.nix` (`blkid`), and build the system on trigkey.
4. `nix copy --to "ssh://root@<ip>?remote-program=/root/.nix-profile/bin/nix-store" <toplevel>`
5. On the VPS: put the host key at `/etc/ssh/ssh_host_ed25519_key` (mode 600). It must be the key whose age key is the host's entry in `.sops.yaml` (`&racknerd`, `&racknerd-pangolin`), or sops cannot decrypt.
6. On the VPS: `nix-env -p /nix/var/nix/profiles/system --set <toplevel>`, `touch /etc/NIXOS`, list `etc/ssh/ssh_host_ed25519_key` and `.pub` in `/etc/NIXOS_LUSTRATE`, plus `var/lib/pangolin` on node 1 (its data, copied there with the stack stopped), then `NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot` and reboot.

The first boot moves the old system to `/old-root`. Delete it when the host works.
