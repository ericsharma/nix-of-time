# Plan: Pangolin EE cluster on the two RackNerd nodes

Status: 2026-10-27 — **production runs on the cluster.** Both nodes run EE 1.25.3 (`pangolin-node/cluster.nix`) on trigkey's PostgreSQL + Valkey; every public name has an A record for BOTH nodes; node 2 is the ACME client. Owner skipped the test resource and the gradual move: production went over in one step. 33 of 40 resources answer; the other 7 were already broken before the move (6 dead backends on trigkey, `stitch` has no target). Failover tested 2026-10-27: node 1 stack stopped → trigkey/gmktec Newt moved to node 2 in 223 s, the mini (Newt 1.15.0) in ~330 s; all working hostnames answered through node 2; no fail-back needed when node 1 returned. Left: rotate the Cloudflare token, remove `cluster.ericsharma.xyz` and the stale `screen.ericsharma.xyz` (old RustDesk), delete `/old-root` on both nodes.

### What the move needed that is NOT in Nix (redo by hand on a rebuilt database)

- Domains are type `wildcard` (A records, no NS delegation). Upstream stores their expected A values as the text `Server IP Address`, which the validator compares literally and never matches. Fixed in `"dnsRecords"`: wildcard rows → `172.245.86.223`; apex rows deleted for `ericsharma.xyz` (Vercel) and `blindjoe.xyz` (none). Then `POST /org/homelab/domain/<id>/restart`.
- Certificates: one row per domain, `domain = <base domain>` (no `*.` — the ACME client adds it), `wildcard = true`. The per-host rows Pangolin made first were deleted: each would need its own `_acme-challenge` CNAME.
- Cloudflare: `_acme-challenge.<zone>` CNAME → `_acme-challenge.<domainId>.cname.ericsharma.xyz` in all 4 zones; `ns` A and `cname` NS in ericsharma.xyz.
- Sites were made by API with production's nice IDs and the **existing** Newt credentials, so no Newt config changed. Newt must be ≥ 1.12 (25.11's 1.5.2 never registers a tunnel with the cluster): trigkey and gmktec use `pkgs.unstable.fosrl-newt`; the mini runs 1.15.0 from `/Library/LaunchDaemons/com.ericsharma.newt.plist`.
- Resources came from the CE blueprint export (`~/backups/racknerd-2026-10-27/ce-blueprints.yaml`), applied with `PUT /v1/org/homelab/blueprint` as base64 JSON. API key: `pangolin-api.key` in `secrets/pangolin.yaml`; the API is only reachable inside the container (`podman exec pangolin curl localhost:3003/v1/...`).

Sources: upstream docs `self-host/clustering/*` (fosrl/docs) and `config/ha-reference/` (fosrl/pangolin). Read them again before each phase; clustering is new upstream and changes often.

## Decisions

| | Decision | Why |
|---|---|---|
| Edition | Enterprise, free personal-use key (owner has it) | Clustering is EE-only: CE images delete `server/private/` |
| Scope | Full cluster, phases A–D | Owner's choice (2026-10-27) |
| PostgreSQL + Valkey | On trigkey | Free, RAM to spare, restic already backs trigkey up. Home is then a single point of failure, but every backend is at home too |
| Internal network | Plain WireGuard in Nix: trigkey + 2 nodes, `10.100.0.0/24` | Tailscale would put public VPSs in the tailnet, next to every device. 3 peers, keys in sops, trigkey dials out (no port opens at home) |
| Data move | Rebuild, not convert | No SQLite → PostgreSQL tool upstream. Resources move as blueprints (`exportBlueprints` CLI); users, roles and the 3 sites are made again |

## Target

| Host | WireGuard | Runs |
|---|---|---|
| trigkey | `10.100.0.1` | PostgreSQL (db `pangolin`), Valkey; both listen on `10.100.0.1` only |
| racknerd-pangolin (node 1) | `10.100.0.11` | Pangolin EE (`ee-postgresql-<ver>`), Gerbil, Traefik (`file_mode`) |
| racknerd (node 2) | `10.100.0.12` | the same |

DNS (Cloudflare stays authoritative for the zones):

| Record | Value | Note |
|---|---|---|
| `ns.ericsharma.xyz` A | node 1 + node 2 IPs | Pangolin's DNS server; resolvers try both |
| `cname.ericsharma.xyz` NS | `ns.ericsharma.xyz` | Delegated to Pangolin |
| each resource hostname | CNAME into `cname.ericsharma.xyz` | Replaces the wildcard A records, one host at a time |
| `pangolin.ericsharma.xyz` A | node 1 + node 2 IPs | Upstream wants an HA load balancer here. Round robin is NOT supported upstream: test it in phase C |

## Known gaps (check before the phase that needs them)

- **RAM:** upstream recommends 2 GB per node; ours have 957 MB. Node 1 uses ~600 MB with CE today. Watch `free -m` and swap in phase A.
- **Raw TCP `:5432` resource:** the HA reference sets `allow_raw_resources: false`. Find out in phase A if it works in a cluster; if not, the owner decides.
- **Dashboard TLS:** upstream terminates it at the load balancer; the nodes' ACME client only covers resource domains. Without a load balancer, each node's Traefik needs its own dashboard certificate (Cloudflare DNS-01, as today).
- **MaxMind GeoLite2** Country + ASN databases are required on each node. Needs a free MaxMind account and license key (owner).
- **Only Newt sites** work in a cluster. Today's 3 sites are Newt: OK.
- `server.secret` must be the same on every node: it is already `pangolin.env` in `secrets/pangolin.yaml`.

## Phase A — test cluster on node 2 (production untouched), 3–4 h

1. WireGuard module `hosts/nixos/optional/`-style but imported explicitly: trigkey (keepalive to both nodes), node 1, node 2. Keys in sops (trigkey's in `secrets.yaml`, nodes' in `pangolin.yaml`). Check: `ping 10.100.0.1` from both nodes.
2. trigkey: `services.postgresql` (db + user `pangolin`, password in sops, `listen_addresses = 10.100.0.1`, `pg_hba` for `10.100.0.11/32`, `.12/32` only), `services.redis.servers.pangolin` (Valkey-compatible, `bind 10.100.0.1`, password). Firewall: open 5432/6379 on `wg-pangolin` only.
3. Node 2: `pangolin-node/cluster.nix` from the HA reference: image `ee-postgresql-<ver>`, `privateConfig.yml` (redis, `use_pangolin_dns`, `acme.cert_mode: pangolin`, `dns`), `config.yml` with `postgres`, `traefik.file_mode`, `site_types: [newt]`, MaxMind paths. Gerbil `--reachableAt=http://10.100.0.12:3004`, `--trusted-upstreams=<both public IPs>`, ports 53/udp, 443→8443, 3004 (WireGuard only).
4. Owner: activate the license in the dashboard (Server Admin → License).
5. Cloudflare (owner, or Claude with the token after an explicit OK): `ns.ericsharma.xyz` A → node 2 only for now; `cname.ericsharma.xyz` NS → `ns.ericsharma.xyz`.
6. Test resource: `clustertest.ericsharma.xyz` CNAME into the cluster, a second Newt on gmktec as a new site, a static page target. Check: `curl https://clustertest.ericsharma.xyz`, then answer the raw TCP and RAM questions.

Rollback: `nixos-rebuild` node 2 back to the spare config; delete the 2 DNS records. Production never moved.

## Phase B — move production into the cluster (node 2 serves), 3–4 h

1. `exportBlueprints` on node 1 (CE) → YAML. Read it; secrets in it (resource passwords, header auth) go to sops, not git.
2. On the cluster: make the users and the 3 Newt sites with the same nice IDs; put the new Newt IDs/secrets in sops for trigkey and gmktec (`newt*/env`) — do not deploy yet.
3. Apply the blueprint on the cluster.
4. Per hostname: switch trigkey's and gmktec's Newt to the cluster (deploy), then move the DNS records from the wildcard A to CNAMEs, a few at a time, `curl` each. Rollback per record: put the A record back.
5. Dashboard A record → node 2.

## Phase C — node 1 joins, 1–2 h

1. Stop CE on node 1; keep `/var/lib/pangolin` as a tarball on trigkey.
2. Deploy the cluster config to node 1 (`--reachableAt=http://10.100.0.11:3004`).
3. Add node 1's IP to `ns.` and the dashboard records.
4. Failover test: stop the stack on node 2; Newt sites must reconnect to node 1 and every hostname must answer. Then the other way round.

## Phase D — clean up, 1 h

1. PostgreSQL dump on a timer into trigkey's restic set.
2. Remove `pangolin.nix` (CE) and SQLite notes; `docs/services/pangolin.md` describes the cluster; `docs/fleet/pangolin-nodes.md` updated.
3. Delete `/old-root` on both nodes.

## Owner actions, in order of need

1. MaxMind account + license key (phase A step 3).
2. EE license key at hand (phase A step 4).
3. Cloudflare record changes, or an explicit OK for Claude to make them with the API token (phase A step 5 onward).
