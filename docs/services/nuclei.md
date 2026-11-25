# Security checks (Nuclei + Pangolin SSO)

Two timers on trigkey test every public Pangolin resource from outside. The hostname list comes from the `pangolin` database, so a route added in the dashboard is covered on the next run. Module: `hosts/nixos/trigkey/nuclei.nix`.

| Check | When | Alert (folder `alerts`, group `security`) |
|-------|------|-------------------------------------------|
| `pangolin-sso-check`: anonymous `GET /` to every SSO-on resource must get 401 or a redirect to `pangolin.ericsharma.xyz/auth/` | hourly | **Pangolin SSO not enforced** (critical) |
| `nuclei-scan`: [Nuclei](https://github.com/projectdiscovery/nuclei) automatic scan (`-as`), no intrusive/dos/fuzz templates, 30 req/s | Sundays 04:00 | **Nuclei finding** for medium and above (warning) |
| Either timer stopped | — | **Security checks not running** (warning) |

Alerts arrive as Home Assistant notifications.

## Run by hand

```bash
sudo systemctl start pangolin-sso-check && cat /var/lib/node-exporter-textfile/pangolin_sso.prom
sudo systemctl start nuclei-scan        # 20–40 min; journalctl -fu nuclei-scan
```

## Read the findings

```bash
sudo jq -r '[.info.severity, ."template-id", ."matched-at"] | @tsv' /var/lib/nuclei/findings.jsonl | sort
```

Info findings (tech detection, panels) are in the file but do not alert.

## Triage

1. A real problem: fix the service or its Pangolin route.
2. Accepted (false positive, or intended): add the template id to `ignoredTemplates` in the module with a comment saying why, then `rebuild`.

## Fix

| Symptom | Check |
|---------|-------|
| SSO alert on many hosts at once | The `badger` middleware. `nix.yml` must not define a middleware named `badger` (see the comment in `pangolin-node/cluster.nix`). On a node: `podman logs traefik \| grep "already configured"` |
| SSO alert on one host | That resource's policy in the dashboard, then `curl -sI -H 'Accept: text/html' https://<host>/` |
| `nuclei-scan` fails at start with "no targets" | The `pangolin` database query in `listTargets`; the schema may have changed in a Pangolin upgrade |
