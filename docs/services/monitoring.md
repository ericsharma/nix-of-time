# Monitoring

Prometheus and Grafana run on trigkey (`hosts/nixos/optional/monitoring.nix`).

`hosts/nixos/optional/monitoring/exporters.nix` provides both node exporter and
cAdvisor. A host gets them when it imports that module. trigkey and gmktec do.
`docker-services` does not — it runs cAdvisor as a Docker container instead
(`hosts/nixos/docker-services/services/cadvisor.nix`).

## Endpoints

| Service | URL | Notes |
|---------|-----|-------|
| Prometheus | `http://trigkey:9090` | Retention is 100y, not 30d |
| Grafana | `http://trigkey:3000` | Admin password from sops (`grafana/env`) |
| Node Exporter | `http://<host>:9100` | Binds `0.0.0.0` by default |
| cAdvisor | `http://<host>:9101` | Binds `0.0.0.0`, set by `exporters.nix` |

Prometheus datasource is auto-provisioned in Grafana.

The NixOS default for `services.cadvisor.listenAddress` is `127.0.0.1`. A host
scraped by LAN address then refuses the connection. `exporters.nix` overrides
the default to `0.0.0.0`, which matches the firewall rule in the same module.

## Adding a scrape target

Add the host to `inventory.nix` at the repo root. `mkTargets` in
`monitoring.nix` maps over `inventory.hosts` and makes a `node` target and a
`cadvisor` target for each one. Then rebuild trigkey.

Check the result:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/targets?state=active' \
  | python3 -c "import json,sys;[print(t['labels']['job'], t['labels'].get('instance'), t['health']) for t in json.load(sys.stdin)['data']['activeTargets']]"
```

## Known gap: docker-services node exporter

`mkTargets` makes a `node` target for every inventory host. But
`docker-services` never imports `exporters.nix`, so nothing answers on port
9100 there. That target reports `down` permanently.

A plain import does not fix it. `exporters.nix` also starts a NixOS cAdvisor,
which collides on port 9101 with the cAdvisor container already in the LXC. A
correct fix enables node exporter alone on that host.

## Dashboards

### Node Exporter Full (Grafana ID 1860)

- Data source: `node_exporter` on each host (port 9100)
- Panels: CPU usage per core, memory/swap, disk I/O and space, network traffic, system load, systemd service states, filesystem usage, hardware temperatures
- Use the `instance` dropdown to switch between hosts (trigkey, gmktec, docker-services)

### Docker monitoring

- Data source: cAdvisor inside docker-services LXC (port 9101)
- Panels: CPU usage, memory consumption, network I/O, disk reads/writes per named container
- Only covers containers inside `docker-services` — Podman containers on trigkey are not instrumented with Docker-level labels

### Portless Services (`portless-services`)

Every `<alias>.local` name published on the LAN, from both hosts, and whether it
answers right now. A table of live status with the HTTP code, a state timeline
of availability, and probe response times.

- Data source: `blackbox_exporter` on trigkey (127.0.0.1:9115), job `portless`
- Probe interval: 30s
- The probe goes **through each host's portless proxy**, not straight to the
  service port. That is deliberate — it catches a dead backend (the proxy
  answers 502) *and* a route the daemon has forgotten (404), which a direct
  port check would miss. It is the same path a browser takes.
- `401`/`403` count as up: a LAN UI behind a login is running. `502` does not.
- Redirects are not followed. Jellyfin answers `302` to a `*.local` URL, and
  blackbox resolves names with Go's own resolver, which does not read
  nss-mdns — chasing it would fail on DNS and report a healthy service as down.

`finance.local` is red whenever the local-finance dev server is not running.
The alias is static; the server is started by hand. That is expected, not a
fault.

## Adding a portless probe

Add the alias to `portlessAliases` for the host in `inventory.nix`, as
`<alias> = { port = <port>; name = "<human name>"; };`. That one entry produces
the mDNS name, the blackbox module, the scrape target, and the dashboard row.
Rebuild the host that publishes it, then rebuild trigkey for the probe.

The alias key is the mDNS name and stays a slug; `name` is what the dashboard's
Service column and the timeline legends show, and defaults to the alias if
omitted. It rides along as the `service_name` label on every `portless` series.

```bash
curl -s -G 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode 'query=probe_success{job="portless"}' \
  | python3 -c "import json,sys;[print(m['metric']['service_name'], m['metric']['alias'], m['value'][1]) for m in json.load(sys.stdin)['data']['result']]"
```

## Trap: the Prometheus datasource uid

`services.grafana.provision.datasources` pins `uid = "Prometheus"`. Leave it
pinned. Without an explicit uid Grafana mints a random one, and while dashboards
survive that (the frontend falls back to a lookup by name), **alert rules do
not** — they evaluate server-side, where the uid is the only key. All three
alert rules in `monitoring.nix` sat in `health=error`, "data source not found",
from the day they were provisioned until 2026-09-10. The disk-full alerts had
never been able to fire.

Changing the uid on a Grafana that already has that datasource under a different
uid does not migrate — provisioning fails and `grafana.service` will not start.
Update the row by hand first, or use `deleteDatasources` for one deploy. The
comment above the option in `monitoring.nix` has the exact commands.

Check rule health after touching any of this:

```bash
PW=$(sudo grep -oP 'GF_SECURITY_ADMIN_PASSWORD=\K.*' /run/secrets/grafana/env)
curl -s -u "admin:$PW" 'http://127.0.0.1:3000/api/prometheus/grafana/api/v1/rules' \
  | python3 -c "import json,sys;[print(r['name'], r.get('health'), r.get('lastError') or '') for g in json.load(sys.stdin)['data']['groups'] for r in g['rules']]"
```
