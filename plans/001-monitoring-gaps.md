# Plan 001: Alerts reach you when trigkey dies, a disk fills, a unit fails, or backups go stale

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 2625ad7..HEAD -- hosts/nixos/optional/monitoring.nix hosts/nixos/optional/monitoring/exporters.nix hosts/nixos/trigkey/backup.nix hosts/nixos/docker-services/default.nix inventory.nix`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M (about 2–3 hours)
- **Risk**: LOW (adds rules and one exporter; changes no existing rule's behaviour)
- **Depends on**: none
- **Category**: bug (observability gap)
- **Planned at**: commit `2625ad7`, 2026-11-24

## Why this matters

All alerting runs on trigkey: Prometheus, Grafana and the only contact point
(Home Assistant on `127.0.0.1:8123`). If trigkey crashes or loses power,
nothing tells the owner — and trigkey also carries the Pangolin cluster DB,
Immich, Vaultwarden and every backup job. Disk alerts cover only gmktec `/`;
a full trigkey root (Postgres) or a full backup T7 is found only by its outage.
The only systemd alert is for failed restic units on trigkey, so other failed
units and "backup timer stopped running" go unnoticed. The docker-services
node target is permanently down (no exporter there), which trains the owner
to ignore "down" targets.

## Current state

- `hosts/nixos/optional/monitoring.nix` — Prometheus + Grafana on trigkey
  (trigkey imports every file in `hosts/nixos/optional/` recursively).
  - Lines 30–120: `freeSpaceRule` helper. The query is hardcoded to gmktec:
    ```nix
    # monitoring.nix:76
    expr = "node_filesystem_avail_bytes{instance=\"gmktec\",mountpoint=\"/\"} / node_filesystem_size_bytes{instance=\"gmktec\",mountpoint=\"/\"} * 100";
    ```
    and `labels.host = "gmktec"`, `__dashboardUid__ = "media-storage"`, `__panelId__ = "5"`.
  - Lines 122–~200: `backupRule` helper (`uid, title, expr, forDuration, summary`), `labels.host = "trigkey"`, severity critical, `noDataState = "OK"`.
  - Lines 316–327: `mkTargets port` builds one scrape target per entry in `inventory.hosts`, labelled `instance = <name>`.
  - Lines ~431–438: jobs `node` (`mkTargets 9100`) and `cadvisor` (`mkTargets 9101`).
  - Lines 623–648: one contact point `home-assistant` (webhook to `http://127.0.0.1:8123/api/webhook/${haWebhookId}`), one policy, `repeat_interval = "24h"`.
  - Lines ~660–800: rule groups `storage` (gmktec-disk-low, gmktec-disk-critical, gmktec-exporter-down) and `backups` (trigkey-restic-failed, trigkey-immich-disk-missing). Exemplar of a non-helper rule: `gmktec-exporter-down` (A=query, B=reduce last, C=threshold).
  - Comment at the `$$labels` summary: `$$` escapes `$` from Grafana's env-var expansion of provisioning files. Keep doing that.
- `hosts/nixos/optional/monitoring/exporters.nix` — node_exporter :9100 (collectors `systemd`, `processes`) + cAdvisor :9101. Imported by trigkey (glob) and gmktec (`hosts/nixos/gmktec/default.nix:17`). **Not** imported by docker-services.
- `hosts/nixos/trigkey/backup.nix` — `services.restic.backups` jobs: `databases` (01:30), `lxc-databases` (01:40), `immich` (02:00), `garage` (03:00), `docker-services` (04:00), `system-state` (04:30, prunes + checks). Units are named `restic-backups-<job>.service`.
- `hosts/nixos/docker-services/default.nix` — the Incus LXC (10.0.100.10). Docker inside; a cAdvisor *container* already publishes 9101 (`services/cadvisor.nix`). No node_exporter. Live Prometheus shows `up{job="node",instance="docker-services"} == 0`.
- `inventory.nix` — `hosts.{trigkey,docker-services,gmktec}.address`. Scrape list comes from here.
- Conventions (from `CLAUDE.md`): bind services to 127.0.0.1; open firewall ports only where truly needed, scoped by interface or source; every non-obvious line gets a "why" comment in the module; conventional commits, lowercase prefix.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Format check | `nix fmt -- --check .` | exit 0 |
| Eval all hosts | `nix flake check --no-build` | exit 0 |
| Build trigkey | `nix build .#nixosConfigurations.trigkey.config.system.build.toplevel --no-link` | exit 0 |
| Build docker-services | `nix build .#nixosConfigurations.docker-services.config.system.build.toplevel --no-link` | exit 0 |
| Build gmktec | `nix build .#nixosConfigurations.gmktec.config.system.build.toplevel --no-link` | exit 0 |
| Deploy (operator only) | trigkey: `nh os switch .`; LXC: `rebuild-docker`; gmktec: `nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo` | exit 0 |

If `nixfmt`/`python3` are not on PATH, wrap in `nix develop -c <cmd>`.

## Scope

**In scope**:
- `hosts/nixos/optional/monitoring.nix`
- `hosts/nixos/optional/monitoring/exporters.nix`
- `hosts/nixos/trigkey/backup.nix` (only adding a success-timestamp hook; no path or schedule changes)
- `hosts/nixos/docker-services/default.nix` (node_exporter only)
- `hosts/nixos/optional/heartbeat.nix` (create)
- `docs/services/monitoring.md` if it exists (one short section on the new alerts); otherwise skip docs

**Out of scope**:
- The Pangolin VPSs (`hosts/nixos/pangolin-node/`, `racknerd*/`). Monitoring them is a follow-up (see Maintenance notes); deploying to the public edge needs separate care.
- `hosts/nixos/optional/homeassistant.nix` — the HA automation keeps working unchanged.
- `hosts/nixos/docker-services/services/cadvisor.nix` — its hardening belongs to another plan.
- Backup paths, schedules, retention.

## Git workflow

- Commit directly on `main` (the owner's rule for this repo); push after each commit.
- Conventional commits, e.g. `feat(monitoring): alert on trigkey and backup disk free space`.
- One commit per step below is fine.

## Steps

### Step 1: Generalise `freeSpaceRule` and add disk rules for the other critical filesystems

Add parameters `instance`, `mountpoint`, `dashboardUid ? "media-storage"`, `panelId ? "5"` to `freeSpaceRule`. Build `expr` from them and set `labels.host = instance`. Keep the gmktec rules identical in effect by passing `instance = "gmktec"; mountpoint = "/";`.

Only set the `__dashboardUid__`/`__panelId__` pair on the gmktec rules (the existing comment says Grafana refuses the file if only one is set; it is fine to omit both). Use `lib.optionalAttrs` so non-gmktec rules carry neither.

Add these rules in the `storage` group (thresholds: warning 15 %, critical 5 %, like gmktec):
- trigkey `/` — `uid = "trigkey-root-disk-low"` / `"trigkey-root-disk-critical"`.
- trigkey `/mnt/immich-data` — `"trigkey-immich-disk-low"` / `"-critical"`.
- gmktec `/mnt/backup` (the T7 with the only backup copy) — `"gmktec-backup-disk-low"` / `"-critical"`.

Each summary says which host and mount, and what runs out (Postgres for trigkey `/`, Immich uploads, nightly restic).

**Verify**: `nix build .#nixosConfigurations.trigkey.config.system.build.toplevel --no-link` → exit 0, and
`grep -cE 'disk-(low|critical)"' hosts/nixos/optional/monitoring.nix` → 8.

### Step 2: Add node_exporter to docker-services

In `hosts/nixos/docker-services/default.nix` add:
```nix
services.prometheus.exporters.node = {
  enable = true;
  port = 9100;
  enabledCollectors = [ "systemd" ];
};
# Prometheus on trigkey scrapes the LXC from the bridge (source 10.0.100.1).
networking.firewall.interfaces.eth0.allowedTCPPorts = [ 9100 ];
```
Do not import `../optional/monitoring/exporters.nix` here: it also starts a cAdvisor service on 9101, which collides with the existing cAdvisor container, and its firewall rule needs nftables.

Before writing the firewall line, confirm the LXC's interface name: `ssh root@10.0.100.10 ip -br link` → shows `eth0`. If it is not `eth0`, STOP.

**Verify**: `nix build .#nixosConfigurations.docker-services.config.system.build.toplevel --no-link` → exit 0.

### Step 3: Alert on any failed systemd unit, fleet-wide

Add a rule group `units` (folder `alerts`, interval `5m`) with one rule, `uid = "unit-failed"`:
- expr: `node_systemd_unit_state{state="failed"} == 1`
- for: `15m` (lets `Restart=` loops settle)
- labels: set only `severity = "warning"`. Do not set a `host` label; the query's own `instance` label is carried into the alert and identifies the host.
- summary: `{{ $$labels.name }} is failed on {{ $$labels.instance }}. Read: journalctl -u {{ $$labels.name }}`
- `noDataState = "OK"` (no failed units → no series → no alert).

Model it on `backupRule`'s A/B/C data structure, but write it inline (backupRule hardcodes `host = "trigkey"`). Keep the existing `trigkey-restic-failed` rule; it is critical severity and fires at 0 s.

**Verify**: trigkey build → exit 0.

### Step 4: Record backup success time and alert when a job is older than 36 h

1. In `exporters.nix`, enable the textfile collector:
   ```nix
   extraFlags = [ "--collector.textfile.directory=/var/lib/node-exporter-textfile" ];
   ```
   and a tmpfiles rule `"d /var/lib/node-exporter-textfile 0755 root root -"`. Add a comment: backup jobs write their last-success time here.
2. In `backup.nix`, for each job name in `databases lxc-databases immich garage docker-services system-state`, add (via `lib.genAttrs` over a list, after the `services.restic.backups` block):
   ```nix
   systemd.services."restic-backups-${job}".serviceConfig.ExecStartPost = [
     # Runs only when the backup succeeded. Read by the "backup stale" alert.
     "${pkgs.writeShellScript "restic-${job}-stamp" ''
       f=/var/lib/node-exporter-textfile/restic_${lib.replaceStrings ["-"] ["_"] job}.prom
       echo "restic_last_success_timestamp_seconds{job=\"${job}\"} $(date +%s)" > "$f.tmp"
       mv "$f.tmp" "$f"
     ''}"
   ];
   ```
   Check first that the nixpkgs restic module does not already set `ExecStartPost` in a way a list would conflict with: `nix eval .#nixosConfigurations.trigkey.config.systemd.services.restic-backups-system-state.serviceConfig.ExecStartPost` → if it errors with a type conflict after your change, use `lib.mkAfter`.
3. In `monitoring.nix`, add a `backupRule` named `uid = "trigkey-restic-stale"`:
   - expr: `time() - restic_last_success_timestamp_seconds{instance="trigkey"} > 36 * 3600`
   - forDuration `30m`
   - summary: `restic job {{ $$labels.job }} has not succeeded for over 36 h.`
   Note: the first night after deploy, the metric does not exist yet and `noDataState = "OK"` keeps it quiet. Also add an `absent(...)` rule per job only if the operator asks; do not add it now.

   Note the label clash: Prometheus' scrape adds its own `job="node"` label. The textfile metric's `job` label will be renamed to `exported_job`. Use `exported_job` in the summary instead of `job` — check with the query in "Done criteria" after deploy and adjust the summary if the label name differs.

**Verify**: trigkey build → exit 0; gmktec build → exit 0 (exporters.nix is shared).

### Step 5: Off-box heartbeat (dead-man's switch)

The operator must first create a check at an external dead-man service (recommended: healthchecks.io free tier, period 10 min, grace 10 min, notify by email and phone push) and add its ping URL to sops as scalar `heartbeat/url` in `secrets/secrets.yaml` (`sops secrets/secrets.yaml`). **If `sops -d --extract '["heartbeat"]["url"]' secrets/secrets.yaml` fails, STOP and ask the operator to do this — never invent a URL.**

Create `hosts/nixos/optional/heartbeat.nix`:
- `sops.secrets."heartbeat/url" = { };`
- `systemd.services.heartbeat` (oneshot, `DynamicUser = true`, `LoadCredential = "url:${config.sops.secrets."heartbeat/url".path}"`) whose script pings the URL only if Grafana answers healthy:
  `curl -fsS -m 10 http://127.0.0.1:3000/api/health >/dev/null && curl -fsS -m 10 --retry 3 "$(cat "$CREDENTIALS_DIRECTORY/url")" >/dev/null`
  (check Grafana's port in `monitoring.nix` `settings.server.http_port` and use that value).
- `systemd.timers.heartbeat` with `OnBootSec = "2m"; OnUnitActiveSec = "5m";`.
- Header comment: why this exists (alert path that does not depend on trigkey).

**Verify**: trigkey build → exit 0; `grep -n heartbeat hosts/nixos/optional/heartbeat.nix | head -3` shows the unit.

### Step 6: Deploy (operator) and check

Operator runs: `nh os switch .` (trigkey), `rebuild-docker` (LXC), gmktec remote switch. Then the checks in Done criteria.

## Test plan

There are no unit tests for Nix modules in this repo. Testing is: build every affected host, then query live Prometheus/Grafana after deploy:
- Disk rule: temporarily lower nothing; instead confirm the rule evaluates — Grafana UI → Alerting → rules list shows all new uids in state Normal.
- Failed-unit rule: `sudo systemd-run --unit=alert-test /bin/false` on trigkey → after ~15–20 min a notification arrives; then `sudo systemctl reset-failed alert-test`.
- Heartbeat: `sudo systemctl stop heartbeat.timer` → the external service alerts within ~20 min; restart the timer.

## Done criteria

- [ ] `nix fmt -- --check .` exits 0
- [ ] `nix flake check --no-build` exits 0
- [ ] trigkey, docker-services, gmktec toplevels build
- [ ] After deploy: `curl -s 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=up{job="node"}'` shows `1` for trigkey, docker-services and gmktec
- [ ] After the next 04:30 backup: `curl -s 'http://127.0.0.1:9090/api/v1/query' --data-urlencode 'query=restic_last_success_timestamp_seconds'` returns 6 series
- [ ] `systemctl list-timers heartbeat.timer` shows the timer active on trigkey
- [ ] `plans/README.md` status row updated

## STOP conditions

- `freeSpaceRule`, `backupRule` or the contact point block does not match the excerpts above.
- The heartbeat sops secret does not exist (Step 5).
- The LXC interface is not `eth0`.
- Grafana fails to start after deploy (`systemctl status grafana`): Grafana refuses the whole provisioning file on one bad rule. Roll back with `sudo nixos-rebuild switch --rollback` and report the journal error.
- Any build fails twice after a reasonable fix.

## Maintenance notes

- A new restic job in `backup.nix` must be added to the Step 4 job list, or it gets no staleness alert.
- Follow-up deferred: monitor the two Pangolin VPSs (node_exporter bound to their wg-pangolin IPs 10.100.0.11/.12, added to `inventory.hosts`). Deferred because it means a deploy to the public edge and adds new hosts to `inventory.hosts`, which other modules also read (portless probes).
- Reviewer: check that no new rule uses `noDataState = "Alerting"` except where a missing series really means trouble; the existing comment explains why disk rules use OK.
