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
