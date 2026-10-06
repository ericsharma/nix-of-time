# CLAUDE.md

Conventions for working in this repo. Depth lives in `docs/`.

## Deploy what you touched

| Touched | Run |
|---------|-----|
| `hosts/nixos/trigkey/`, `hosts/nixos/common/`, `inventory.nix` | `rebuild` |
| `hosts/nixos/optional/` | `rebuild`, plus gmktec if it imports the changed module |
| `hosts/nixos/docker-services/` | `rebuild-docker` (works from trigkey only) |
| `hosts/nixos/gmktec/` | `nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo` |
| New stateful docker-services service | `rebuild` first (host dir + Incus disk mount in `hosts/nixos/trigkey/containers.nix`), then `rebuild-docker` |

- `trigkey`, `docker-services`, and `gmktec` are separate `nixosConfigurations`. Editing one changes nothing elsewhere until you deploy it.
- `git add` new files before building. The flake ignores untracked files.
- Sudo is passwordless for `eric` on trigkey and gmktec. Run `rebuild`, `nh os switch`, `systemctl`, `journalctl` directly. `rebuild-docker` reaches the LXC as `root@10.0.100.10`, so it is non-interactive too.

## Where a service goes

Criteria: [docs/architecture.md](docs/architecture.md#when-to-use-which). First match wins:

1. Native NixOS module exists → `hosts/nixos/optional/<svc>.nix`
2. Single container, no sidecar DB → Podman module in `hosts/nixos/optional/`
3. Multi-container, needs inter-container DNS → Docker stack in `hosts/nixos/docker-services/services/<svc>.nix`
4. Bound to trigkey's hardware or storage (Immich, Garage, backup, the Incus launcher) → `hosts/nixos/trigkey/`
5. Meant for gmktec only → `hosts/nixos/gmktec/`

**Never** copy trigkey's `listFilesRecursive` import of `optional/` to another host. Those modules have no enable flags. List imports explicitly, as `hosts/nixos/gmktec/default.nix` does.

Grafana dashboard JSON: `hosts/nixos/optional/dashboards/`. Exporters: `hosts/nixos/optional/monitoring/`.

## sops

- One file, `secrets/secrets.yaml`, decrypted by each system with its own age key (from its SSH host key).
- LXC secrets live under the `docker-services:` namespace.
- Env block, for `environmentFile` consumers: `service.env: |` then `KEY=value` lines.
- Scalar, for path-to-one-secret consumers: `service.<name>: <value>`.
- Declare in the module: `sops.secrets."service/env" = {};` (or `"service/<name>"`). LXC secrets are declared in `hosts/nixos/docker-services/sops.nix`.

## Networking

Bind services to `127.0.0.1`. Public exposure goes through Newt → Pangolin, with zero open ports. Open a firewall port only when LAN access is truly needed.

## Commits

Conventional commits, lowercase prefix: `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`. Subject-only is fine; add a body when *why* matters.

## Claude Code skills

- Custom skills live in `~/.claude/skills/<name>/SKILL.md` (in `$HOME`, not this repo). Index: [docs/claude-skills.md](docs/claude-skills.md).
- `/garage` is the recipe for adding Garage S3 storage to a service.
- After creating or editing a skill, run `scripts/backup-claude-skills` and commit `secrets/claude-skills.tar.gz`. It is the only off-machine copy.
