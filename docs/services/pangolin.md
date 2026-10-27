# Pangolin

Reverse proxy and tunnel server for every public service. Newt on trigkey and gmktec dials in; Traefik terminates TLS for all domains.

| | |
|---|---|
| Host | racknerd-pangolin, `172.245.86.223` ([Pangolin nodes](../fleet/pangolin-nodes.md)) |
| Dashboard | <https://pangolin.ericsharma.xyz> |
| Module | `hosts/nixos/pangolin-node/pangolin.nix` |
| Edition | Community (`fosrl/pangolin:<version>`) |
| Data | `/var/lib/pangolin`: `db/db.sqlite`, `key` (Gerbil WireGuard key), `letsencrypt/` |
| Secrets | `secrets/pangolin.yaml`: `pangolin.env` (`SERVER_SECRET`), `traefik.env` (`CLOUDFLARE_DNS_API_TOKEN`) |

## Use

- Resources, sites and users: in the dashboard. They live in the database, not in Nix.
- Domains, ACME resolvers, ports, Traefik static config: in the module. A domain in Pangolin must name a resolver that exists in the module's `traefikStatic`.

## Upgrade

1. Read the release notes of every version between the current and the target tag.
2. Change `pangolinImage`, `gerbilImage`, `traefikImage` and `badgerSrc` (rev + hash) together. The installer (upstream `install/Makefile`) pairs each Pangolin release with the newest Gerbil and Badger tags.
3. Copy the database (`/var/lib/pangolin/db/db.sqlite`) before the deploy. A Pangolin database cannot go back a version.
4. Deploy. Migrations run at start: `journalctl -u podman-pangolin`.

Migrations that "update the version of Badger in your Traefik configuration" fail with `ENOENT … traefik_config.yml`. That is expected: the Traefik files come from Nix, so step 2 does that work.

## Fix

| Symptom | Check |
|---------|-------|
| All sites down | `systemctl status podman-pangolin podman-gerbil podman-traefik` |
| Gerbil does not start | It waits for Pangolin's health check in `preStart`: `podman healthcheck run pangolin` |
| Certificate errors | `journalctl -u podman-traefik \| grep -i acme`; the Cloudflare token in `traefik.env` must cover the zone |
| Sites in the dashboard stay offline | Gerbil's WireGuard key changed. `/var/lib/pangolin/key` must survive a reinstall |
| Sites offline after a reboot, Newt logs `Periodic ping failed` | Stale UDP conntrack entries without DNAT (`ss -ulpn \| grep 51820` shows a large Recv-Q). Gerbil's `postStart` deletes them; by hand: `systemctl restart podman-gerbil` |

## Clustering (not done)

Multi-node Pangolin (Redis + PostgreSQL) is in the Enterprise Edition only: upstream deletes `server/private/` from the Community image. The Enterprise Edition is free for personal use. The path:

1. Image `fosrl/pangolin:ee-postgresql-<version>`.
2. Move the SQLite database to PostgreSQL. Upstream has no tool for this in the repo as of 1.25.3.
3. A shared PostgreSQL and Redis that both nodes reach.
