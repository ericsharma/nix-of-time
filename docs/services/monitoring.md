# Monitoring

Prometheus and Grafana run on trigkey (`hosts/nixos/optional/monitoring.nix`) and scrape every host listed in `inventory.nix`.

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | `http://trigkey:3000` | Admin password in sops, `grafana/env` |
| Prometheus | `http://trigkey:9090` | Machine metrics, 90d |
| Prometheus (air quality) | `http://127.0.0.1:9091` | AirGradient only, 100y, loopback |
| node exporter | `http://<host>:9100` | From `optional/monitoring/exporters.nix` |
| cAdvisor | `http://<host>:9101` | Same module; the LXC runs a container instead |

Run the commands on this page on trigkey.

## Add a host

1. Add the host to `inventory.nix`. `mkTargets` creates a `node` and a `cadvisor` target for every host.
2. Import `hosts/nixos/optional/monitoring/exporters.nix` on that host.
3. `rebuild` trigkey, then check:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/targets?state=active' \
  | jq -r '.data.activeTargets[] | "\(.labels.job) \(.labels.instance) \(.health)"'
```

**Known gap:** the `docker-services` `node` target is always `down`. The LXC doesn't import `exporters.nix`, and importing it would start a second cAdvisor on 9101. The fix is to enable node exporter alone there.

## Portless probes

Every `*.local` alias gets a blackbox probe (job `portless`, every 30 s) and a row on the **Portless Services** dashboard.

1. Add the alias to the host's `portlessAliases` in `inventory.nix`: `<alias> = { port = <port>; name = "<Display Name>"; };`
2. Rebuild the host that publishes it.
3. `rebuild` trigkey, then check:

```bash
curl -s -G 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=probe_success{job="portless"}' \
  | jq -r '.data.result[] | "\(.metric.service_name) \(.metric.alias) \(.value[1])"'
```

Reading the results:

- The probe goes through the portless proxy, so it catches a dead backend (502) and a lost route (404).
- `401` and `403` count as up. `502` does not.
- Redirects aren't followed, because blackbox can't resolve `*.local` names.
- `finance.local` is red whenever the dev server isn't running. That's expected.

## Dashboards

- **Node Exporter Full** (Grafana ID 1860): CPU, memory, disk, network, systemd per host. Switch hosts with `instance`.
- **Docker monitoring:** per-container stats from the LXC's cAdvisor. Podman containers aren't covered.
- **Portless Services:** see above.
- **AirGradient:** air quality from the 100y instance, plus TSDB health panels.

## Two Prometheus instances

Retention belongs to a database, not a metric, so air quality gets its own instance.

| Instance | Port | Holds | Retention | Data |
|----------|------|-------|-----------|------|
| `prometheus` | 9090 | node, cAdvisor, blackbox, both self-scrapes | 90d | `/var/lib/prometheus2` |
| `prometheus-airgradient` | 9091 | the nine `airgradient_*` gauges | 100y | `/var/lib/prometheus-airgradient` |

Don't break these:

- **The `airgradient` job lives only in the 100y instance.** Added to 9090, the samples expire after 90 days.
- **Never set `retention.size` on the 100y instance.** It deletes oldest-first.
- **Write 100y as a duration.** `0` means "unset" and falls back to 15d.
- The 100y instance is a plain `systemd.services` unit in `monitoring.nix`, because the NixOS module supports one instance.

Check what's actually running:

```bash
ps -eo args | grep '[p]rometheus --' | grep -o 'retention.time=[^ ]*\|tsdb.path=[^ ]*'
```

### Is history being deleted?

```bash
curl -s -G 'http://127.0.0.1:9090/api/v1/query' \
  --data-urlencode 'query=(time() - prometheus_tsdb_lowest_timestamp_seconds) / 86400' \
  | jq -r '.data.result[] | "\(.metric.job) \(.value[1]) days"'
```

- `job="prometheus"` settles near 90 days while `prometheus_tsdb_time_retentions_total` rises. Normal.
- `job="prometheus-airgradient"` grows by one day per day, and `prometheus_tsdb_time_retentions_total` stays `0`. Anything else means data loss.

Air quality history starts 2026-05-23; ten earlier weeks were lost and the cause was never found. The self-scrape jobs exist so the next loss is visible. Both data directories are in the restic `system-state` job.

## Trap: pinned datasource uids

`monitoring.nix` pins `uid = "Prometheus"` (9090) and `uid = "PrometheusAirGradient"` (9091). Keep both pinned.

- Alert rules find a datasource by uid only. Before the pin, every rule failed with "data source not found" (fixed 2026-09-10).
- Changing a uid on a running Grafana stops `grafana.service` from starting. The comment above the option has the migration commands.
- A panel with no `datasource` uses `Prometheus`, which has no `airgradient_*` series.

Check rule health after any change:

```bash
PW=$(sudo grep -oP 'GF_SECURITY_ADMIN_PASSWORD=\K.*' /run/secrets/grafana/env)
curl -s -u "admin:$PW" 'http://127.0.0.1:3000/api/prometheus/grafana/api/v1/rules' \
  | jq -r '.data.groups[].rules[] | "\(.name) \(.health) \(.lastError // "")"'
```
