# Monitoring

Prometheus and Grafana run on trigkey (`hosts/nixos/optional/monitoring.nix`).

`hosts/nixos/optional/monitoring/exporters.nix` provides both node exporter and
cAdvisor. A host gets them when it imports that module. trigkey and gmktec do.
`docker-services` does not — it runs cAdvisor as a Docker container instead
(`hosts/nixos/docker-services/services/cadvisor.nix`).

## Endpoints

| Service | URL | Notes |
|---------|-----|-------|
| Prometheus | `http://trigkey:9090` | Machine data. Retention 90d |
| Prometheus (AirGradient) | `http://127.0.0.1:9091` | Air quality only. Retention 100y. Loopback only |
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

## Retention — two TSDBs, on purpose

Retention in Prometheus is a property of the database, not of a metric. One
instance cannot keep air quality for a century and cAdvisor for a quarter, so
there are two instances:

| Instance | Port | Holds | Retention | Data |
|----------|------|-------|-----------|------|
| `prometheus` | 9090 | node, cAdvisor, blackbox, both self-scrapes | 90d | `/var/lib/prometheus2` |
| `prometheus-airgradient` | 9091 | the nine `airgradient_*` gauges | 100y | `/var/lib/prometheus-airgradient` |

The air quality instance is a plain `systemd.services` unit in
`monitoring.nix`, not `services.prometheus` — the NixOS module models a single
instance. It runs as the `prometheus` user and scrapes through the same JSON
exporter on 7979.

**The `airgradient` job must exist in exactly one of the two.** It lives in the
100y instance. Adding it back to the main one writes the same samples into a
database that discards them after 90 days.

Verify against the running processes rather than the config:

```bash
ps -eo args | grep '[p]rometheus --' | grep -o 'retention.time=[^ ]*\|tsdb.path=[^ ]*'
# tsdb.path=/var/lib/prometheus2/data/         retention.time=90d
# tsdb.path=/var/lib/prometheus-airgradient/data  retention.time=100y
```

`retention.size` must stay unset on the 100y instance. Adding it re-introduces
deletion, and it deletes oldest-first, which is exactly the history it exists
to hold. 100y is written as a duration because Prometheus reads `0` as "unset"
and falls back to its 15d default.

### Why 90d for everything else

The main TSDB grew to 19 GB in 110 days — about 60 GB a year against 205 GB
free on `/`. Nearly all of it is node exporter and cAdvisor, which answer
"what changed last week" and are worthless after a quarter. The nine air
quality gauges cost about 20 MB a year, so a century of them is roughly 2 GB.

### The 2026-09-11 migration

The split moved the 111 days of air quality history that already existed
(2026-05-23 onward) out of the main TSDB, before the new 90d retention could
trim the oldest three weeks of it. Every `airgradient_*` series was read out
over `/api/v1/query_range`, written as OpenMetrics, turned into blocks with
`promtool tsdb create-blocks-from openmetrics --max-block-duration=24h`, and
copied into the new data directory with the service stopped. 2.88M samples,
149 blocks, 17 MB. The pre-split copy still sits in `/var/lib/prometheus2`
until 90d retention reaches it.

### The data horizon

Every metric in this TSDB begins **2026-05-23**, about ten weeks after the
stack was built. Retention was never the cause: it was `100y` from the first
commit, and `/var/lib/prometheus2` still carries its original 2026-03-12 birth
time, so the directory was not recreated. Ten weeks of data were removed and
nothing recorded what did it — the journal only reaches the current boot
(2026-08-10), and Prometheus was not scraping itself, so there was no stored
history of the TSDB's own state to consult. That data is not recoverable.

The `prometheus` self-scrape job exists to close that gap. Two series answer
"is anything being deleted?":

| Series | Means |
|--------|-------|
| `prometheus_tsdb_lowest_timestamp_seconds` | How far back data goes. |
| `prometheus_tsdb_time_retentions_total` | Blocks dropped for age. |

Read them per instance — the `job` label separates the two. On `job="prometheus"`
(the 90d machine store) the lowest timestamp settles at 90 days back and
`time_retentions_total` rises; that is retention working. On
`job="prometheus-airgradient"` the lowest timestamp must keep sliding back by
one day per day and `time_retentions_total` must stay `0`. Both instances are
scraped by the main one, so both histories age out after 90 days — long enough
to see a problem, and the alternative was keeping ~1000 process metrics for a
century.

Both are process counters that reset on restart, so reading `/metrics` by hand
proves nothing about last month. Stored as series they become a history. The
**AirGradient** dashboard surfaces both as "History retained" and "Blocks
dropped by retention".

```bash
curl -s -G 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode 'query=time() - prometheus_tsdb_lowest_timestamp_seconds' \
  | python3 -c "import json,sys;print(float(json.load(sys.stdin)['data']['result'][0]['value'][1])/86400,'days')"
```

### What actually threatens the history now

Disk was the threat while everything was kept forever; the 90d window on the
main instance removes it. What is left is that the 100y store is a single
directory on one disk, and there is still no alert on trigkey's root
filesystem, so the first sign of trouble would be Prometheus failing to write.

Both `/var/lib/prometheus2` and `/var/lib/prometheus-airgradient` are in the
restic backup set (`hosts/nixos/trigkey/backup.nix`). Only the second one holds
anything that cannot be re-collected.

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

There are now two pinned uids: `Prometheus` (9090) and `PrometheusAirGradient`
(9091). Every panel on the AirGradient dashboard points at the second, except
the two TSDB-health panels, which read the main instance because that is where
both instances' self-metrics are stored. A dashboard that leaves `datasource`
unset falls through to `Prometheus`, the default, and will find no
`airgradient_*` series there.
Update the row by hand first, or use `deleteDatasources` for one deploy. The
comment above the option in `monitoring.nix` has the exact commands.

Check rule health after touching any of this:

```bash
PW=$(sudo grep -oP 'GF_SECURITY_ADMIN_PASSWORD=\K.*' /run/secrets/grafana/env)
curl -s -u "admin:$PW" 'http://127.0.0.1:3000/api/prometheus/grafana/api/v1/rules' \
  | python3 -c "import json,sys;[print(r['name'], r.get('health'), r.get('lastError') or '') for g in json.load(sys.stdin)['data']['groups'] for r in g['rules']]"
```
