# Monitoring

Prometheus and Grafana run on trigkey (`hosts/optional/monitoring.nix`). Node exporter runs on every host (`hosts/common/monitoring/exporters.nix`), and cAdvisor runs inside the docker-services LXC (`hosts/docker-services/services/cadvisor.nix`).

## Endpoints

| Service | URL | Notes |
|---------|-----|-------|
| Prometheus | `http://trigkey:9090` | 30d retention |
| Grafana | `http://trigkey:3000` | Admin password from sops (`grafana/env`) |
| Node Exporter | `http://<host>:9100` | Runs on every host |
| cAdvisor | `http://10.0.100.10:9101` | Docker container metrics |

Prometheus datasource is auto-provisioned in Grafana.

## Adding a scrape target

Add the host to the `nodes` attrset in `hosts/optional/monitoring.nix`.

## Dashboards

### Node Exporter Full (Grafana ID 1860)

- Data source: `node_exporter` on each host (port 9100)
- Panels: CPU usage per core, memory/swap, disk I/O and space, network traffic, system load, systemd service states, filesystem usage, hardware temperatures
- Use the `instance` dropdown to switch between hosts (trigkey, docker-services)

### Docker monitoring

- Data source: cAdvisor inside docker-services LXC (port 9101)
- Panels: CPU usage, memory consumption, network I/O, disk reads/writes per named container
- Only covers containers inside `docker-services` — Podman containers on trigkey are not instrumented with Docker-level labels
