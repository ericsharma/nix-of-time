# racknerd

The public edge: a RackNerd VPS that runs the [Pangolin](../services/pangolin.md) stack and nothing else. Not on the LAN.

```bash
nixos-rebuild switch --flake .#racknerd --target-host root@198.46.199.125   # from trigkey
etd-ssh racknerd '<command>'                                                # a shell command, no ssh key needed
```

| | |
|---|---|
| Address | `198.46.199.125` (DHCP from RackNerd) |
| Hardware | KVM, 1 vCPU, BIOS boot (no EFI) |
| Memory | 957 MB + zram + 1 GB swap partition |
| Storage | 20 GB virtio (`/dev/vda`), layout in `hosts/nixos/racknerd/disk-config.nix` |
| Config | `hosts/nixos/racknerd/`, home: `home/racknerd/` |
| Secrets | `secrets/racknerd.yaml` only |

## What it runs

| Service | Port | Purpose |
|---------|------|---------|
| [Pangolin](../services/pangolin.md) + Gerbil + Traefik | 80, 443 (TCP+UDP), 5432, 51820/udp, 21820/udp | Reverse proxy and tunnels for every public service |
| etd + manymux node | — | E.T. app and `etd-ssh` reach the box |

## How it differs from the other hosts

- **Own sops file.** Its age key opens `secrets/racknerd.yaml` and nothing else. Never add `*racknerd` to the `secrets.yaml` rule in `.sops.yaml`: this host faces the internet.
- **Root login by key, from trigkey only.** Deploys run as root. `eric` keeps a sudo password, because every etd network member can run commands as `eric`.
- **No `listFilesRecursive` of `optional/`.** Imports are explicit, as on gmktec.

## Reinstall

nixos-anywhere ERASES `/dev/vda`. The host SSH key must be the one whose age key is in `.sops.yaml` (`&racknerd`), or sops cannot decrypt on first boot.

```bash
# extra/etc/ssh/ssh_host_ed25519_key = the existing host key (from a backup)
nix run github:nix-community/nixos-anywhere -- --flake .#racknerd \
  --target-host root@198.46.199.125 --extra-files extra --chown /etc/ssh 0:0
```

1 GB RAM is the floor for the kexec step. Stop large services on the old system first.
