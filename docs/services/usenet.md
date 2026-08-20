# Usenet stack (gmktec)

SABnzbd downloads and extracts. Prowlarr manages the indexer and hands
`.nzb` files to SABnzbd. Both run natively on gmktec (`192.168.0.51`).

| Piece | Port | Module |
|-------|------|--------|
| SABnzbd | 8080 (LAN) | `hosts/nixos/gmktec/sabnzbd.nix` |
| Prowlarr | 9696 (LAN) | `hosts/nixos/gmktec/prowlarr.nix` |
| Sonarr | 8989 (LAN) | `hosts/nixos/gmktec/sonarr.nix` |
| Radarr | 7878 (LAN) | `hosts/nixos/gmktec/radarr.nix` |
| Jellyfin | 8096 (LAN) | `hosts/nixos/gmktec/jellyfin.nix` |
| `/data` tree + `media` group | — | `hosts/nixos/gmktec/media-storage.nix` |
| shared reconcile helpers | — | `hosts/nixos/gmktec/servarr-api.nix` |

- <http://192.168.0.51:8080>
- <http://192.168.0.51:9696>
- <http://192.168.0.51:8989>
- <http://192.168.0.51:7878>
- <http://192.168.0.51:8096> — Jellyfin, the only one with real accounts

Prowlarr is the only place an indexer is ever configured. With `syncLevel`
`fullSync` it pushes its indexers into Sonarr and Radarr and keeps them in
step, so both apps show `NZBgeek (Prowlarr)` and neither is edited directly.

Neither asks for a login from the LAN — SABnzbd has no account at all, and
Prowlarr runs `AuthenticationRequired=DisabledForLocalAddresses`. The nftables
rules admit only `192.168.0.0/24`, and gmktec has no Newt route for either
port. Do not put them on the public path without revisiting both of those.

A `curl -I` (HEAD) against Prowlarr answers 401 even from the LAN. That is
normal; use a GET.

## The `/data` tree

```
/data/usenet/incomplete    SABnzbd work area
/data/usenet/complete/*    finished downloads, one directory per category
/data/media/{tv,movies}    library for a later Sonarr/Radarr
```

Everything is one ext4 filesystem on the internal NVMe, group `media`, mode
2775 with the setgid bit. This is a hard requirement, not a preference: an
*arr app finishes an import by making a **hardlink** from the completed
download into the library, and a hardlink cannot cross a filesystem boundary.
Give a future service the same absolute paths, add its user to `media`, and set
`UMask = 0002`. Never give one of these services its own private bind mount or
a second disk.

### The group must be PRIMARY, not supplementary

SABnzbd runs with `media` as its **primary** group (`services.sabnzbd.group`).
Supplementary membership plus the setgid bit looks equivalent and is not.

SABnzbd applies its `permissions = 0775` setting with a `chmod`, and that
strips setgid off every directory it creates. So `/data/usenet/complete/tv`
lost the bit, everything below it was written `sabnzbd:sabnzbd`, and Sonarr —
in `media` but not in `sabnzbd` — could not write those files. Every import
failed and stacked up in the queue as `importPending`, with no error in the
Sonarr log. 68 GB downloaded and one episode imported.

Give any future service in this stack `media` as its primary group. Do not rely
on the setgid bit to carry it.

Test the way SABnzbd actually writes, not with a file you made yourself:

```bash
ssh eric@192.168.0.51 'D=$(find /data/usenet/complete/tv -maxdepth 1 -type d | sed -n 2p)
  F=$(find "$D" -type f -name "*.mkv" | head -1)
  ls -l "$F"
  sudo -u sonarr ln "$F" /data/media/tv/.t && echo OK && sudo -u sonarr rm -f /data/media/tv/.t'
```

`UMask = 0002` matters for a second reason that is easy to miss. NixOS sets
`fs.protected_hardlinks = 1`, so a user may only hardlink a file they could
write. SABnzbd's output must therefore be group-**writable**, not merely
group-readable — `0664`, not `0644` — or every import silently falls back to a
copy, which doubles the disk use and the import time. Verified working:

```bash
ssh eric@192.168.0.51 'sudo -u sabnzbd sh -c "umask 0002; echo t > /data/usenet/complete/.ln-test"
  sudo -u sonarr ln /data/usenet/complete/.ln-test /data/media/tv/.ln-test && echo OK
  stat -c "links=%h inode=%i" /data/media/tv/.ln-test
  sudo -u sonarr rm -f /data/media/tv/.ln-test
  sudo -u sabnzbd rm -f /data/usenet/complete/.ln-test'
```

`/data` is **not** backed up. Every file in it is re-downloadable, and
`/mnt/backup` is reserved for trigkey's restic repository — see
[backup.md](backup.md).

## Config is declarative — the web UIs are not authoritative

**SABnzbd:** `/var/lib/sabnzbd/sabnzbd.ini` is rewritten from
`sabnzbd.nix` by an `ExecStartPre` on **every start**. Credentials are
substituted in from `/run/secrets/` with `replace-secret`, so nothing lands in
the Nix store. A change made in the web UI works until the next restart and is
then gone. Edit the module.

The template's `__version__` must match `CONFIG_VERSION` in the sabnzbd
package (19 for 4.5.x). Check it after a version bump:

```bash
grep CONFIG_VERSION "$(nix build --no-link --print-out-paths \
  ~/nixos-config#nixosConfigurations.gmktec.pkgs.sabnzbd)"/sabnzbd/constants.py
```

**Prowlarr:** `config.xml` comes from `services.prowlarr.settings` as
`PROWLARR__*` environment variables. Indexers and download clients, though,
live in Prowlarr's SQLite database, which no NixOS option reaches.
`prowlarr-reconcile.service` closes that gap: after Prowlarr starts, it reads
the current objects over the REST API and creates or updates the NZBGeek
indexer and the SABnzbd download client to match the module. It is idempotent.

Prowlarr tests an indexer before it saves it, and `?forceSave=true` does not
bypass that (checked against 2.3.5). So this unit **fails** while the NZBGeek
key in sops is wrong or still a placeholder, and the journal quotes Prowlarr's
own reason. That is the wanted behaviour: a dead indexer is never written.

### `Trial Account Only`

NZBGeek gates API search behind a paid membership. A free registration gives a
valid API key that answers `t=caps` but returns `error code="101" Trial Account
Only` for every search, so `prowlarr-reconcile` cannot save the indexer and the
host stays `degraded`. Nothing in this repo needs to change when the account is
upgraded — restart the unit.

Ask NZBGeek itself, without going through Prowlarr:

```bash
ssh eric@192.168.0.51 'K=$(sudo sed -n "s/^NZBGEEK_API_KEY=//p" /run/secrets/prowlarr/env)
  curl -s "https://api.nzbgeek.info/api?t=caps&apikey=$K" | head -c 200; echo
  curl -s "https://api.nzbgeek.info/api?t=tvsearch&apikey=$K" | head -c 200'
```

```bash
ssh eric@192.168.0.51 'systemctl start prowlarr-reconcile && \
  journalctl -u prowlarr-reconcile -n 20 --no-pager'
```

## Servers

Both Frugal connections use SSL on port 563 with `ssl_verify = 3` (strict).

| Section | Host | Connections | Role |
|---------|------|-------------|------|
| `news.frugalusenet.com` | primary backbone | 45 | `priority = 0` |
| `bonus.frugalusenet.com` | bonus block | 20 | `optional = 1` |

`optional = 1` is the **Backup server** checkbox in the SABnzbd UI: the bonus
backbone is queried only for articles the primary could not supply, so block
allowance is spent on fills rather than on the whole download.

Use `newswest.frugalusenet.com` instead of `news.` for West Coast routing.

## Secrets

All in `secrets/secrets.yaml`, decrypted by gmktec's own host key.

| Key | Used by |
|-----|---------|
| `sabnzbd/frugal-username`, `sabnzbd/frugal-password` | rendered into `sabnzbd.ini` |
| `sabnzbd/api-key`, `sabnzbd/nzb-key` | pinned so Prowlarr and the *arrs keep working across rebuilds |
| `prowlarr/env` | `PROWLARR__AUTH__APIKEY` and `NZBGEEK_API_KEY` |
| `sonarr/env` | `SONARR__AUTH__APIKEY` — also read by `prowlarr-reconcile` for the app link |
| `radarr/env` | `RADARR__AUTH__APIKEY` — same |

To change one:

```bash
cd ~/nixos-config
nix develop -c sops set secrets/secrets.yaml '["sabnzbd"]["frugal-password"]' '"newpass"'
nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo
```

Every secret here declares `restartUnits`, so the rebuild restarts whatever
consumes it. That matters most for SABnzbd: its ini is written by an
`ExecStartPre`, so a new credential reaches it **only** on a restart.

This has already bitten once. New Frugal credentials went into sops, the
rebuild wrote them to `/run/secrets`, SABnzbd kept running on the ini it had
rendered at boot, and Frugal answered `502 Access denied to your node` and
`502 Authentication Failed`. Those read like a wrong password or a connection
limit; the real cause was a stale file. If you ever see them, check the ini
before you suspect the account:

```bash
ssh eric@192.168.0.51 'sudo grep -c REPLACE-ME /var/lib/sabnzbd/sabnzbd.ini'
```

Note that `restartUnits` fires only when the secret's value actually changes
during an activation. It cannot repair a drift that already happened — restart
by hand for that.

## Checks

```bash
ssh eric@192.168.0.51 'systemctl status sabnzbd prowlarr prowlarr-reconcile'
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.0.51:8080/
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.0.51:9696/
ssh eric@192.168.0.51 'sudo nft list chain inet nixos-fw input-allow'
ssh eric@192.168.0.51 'df -h /data && ls -la /data/usenet'
```

Frugal server state, from the SABnzbd API:

```bash
ssh eric@192.168.0.51 'K=$(sudo sed -n "s/^api_key *= *//p" /var/lib/sabnzbd/sabnzbd.ini | head -1)
  curl -s "http://127.0.0.1:8080/api?mode=status&output=json&apikey=$K" \
    | jq "[.status.servers[] | {servername, serveractive, serveroptional, servertotalconn, servererror}]"'
```

Note that SABnzbd opens no connection until it has work, so a clean
`servererror` there proves the config, not the login. To prove the login,
authenticate against the backbone directly over TLS on 563 and look for
`281 Authentication accepted`.

## Reconcile units

Three units, one per app, all built on the helpers in `servarr-api.nix`:

| Unit | Creates |
|------|---------|
| `sonarr-reconcile` | root folder `/data/media/tv`, SABnzbd client (category `tv`) |
| `radarr-reconcile` | root folder `/data/media/movies`, SABnzbd client (category `movies`) |
| `prowlarr-reconcile` | NZBgeek indexer, SABnzbd client, Sonarr and Radarr app links |

`prowlarr-reconcile` runs last, because Prowlarr calls an app to test the link
before it saves it. `After=` alone is not enough — it orders unit *starts*, and
only inside one transaction — so `wait_app` polls each app's
`/api/v3/system/status` before the link is written.

Every helper local carries a `_` prefix. Bash has no function scope by default,
and an unprefixed `path` in one helper overwrote the caller's `path` in another,
which made the log claim a root folder named `/rootfolder` had been added.

## Next phase

Nothing is required. Options from here:

- **Recyclarr or custom formats** for quality profiles, if the defaults prove
  too loose.
- **Bazarr** for subtitles, on the same `/data/media` paths and the `media`
  group.
- **Jellyfin on gmktec** pointed at `/data/media`, or an rclone/NFS path from
  the existing trigkey Jellyfin.

## Gotchas

- SABnzbd refuses a request whose `Host` header it does not know. The template
  whitelists `gmktec`, `gmktec.local`, `192.168.0.51`, and loopback. Add any
  new name there, or you get a bare "Access denied" page.
- `unrar` is unfree, and is in sabnzbd's `PATH`. It is allowed by name in
  `hosts/nixos/common/default.nix`. Removing that entry breaks the build, not
  just extraction.
- SABnzbd's `download_dir` and `complete_dir` may not nest inside one another;
  the package validates this and refuses to start.

## Watching storage

Grafana on trigkey, dashboard **Media Storage (gmktec)** — <http://trigkey:3000/d/media-storage>.

`/data` sits on the root filesystem, so `node_filesystem_*` gives one number for
the whole 937 GiB disk and cannot say how much is TV, films, or downloads still
in flight. `hosts/nixos/gmktec/media-metrics.nix` fills that gap: a timer runs
`du` every 15 minutes and writes Prometheus text into node_exporter's textfile
directory, where the existing scrape collects it. No new service, no new port.

Two kinds of number appear on that dashboard, and they deliberately disagree:

- **Free space** comes from the filesystem. This is the truth.
- **Per-category sizes** come from `du`. A file Sonarr hardlinked from
  `/data/usenet/complete` into `/data/media/tv` is one set of blocks on disk but
  is counted in both trees, so these do **not** sum to the space used.

### Alerts

Grafana's own unified alerting — there is no Alertmanager on trigkey and three
rules do not justify adding one.

| Rule | Fires when | For |
|------|-----------|-----|
| `gmktec-disk-low` | below 15% free | 15m |
| `gmktec-disk-critical` | below 5% free | 5m |
| `gmktec-exporter-down` | Prometheus cannot scrape gmktec | 10m |

They post to Home Assistant's webhook, and an automation in
`hosts/nixos/optional/homeassistant.nix` turns each into a persistent
notification. **The webhook id is duplicated in two files** — `monitoring.nix`
and `homeassistant.nix` — and must match. It is `local_only`, so only the LAN
can post to it.

To send a mobile push instead of an HA notification, change the automation's
`persistent_notification.create` to your `notify.*` service.

Test the whole path without waiting for a real alert:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' \
  -d '{"title":"TEST","message":"ignore me","groupKey":"test"}' \
  http://127.0.0.1:8123/api/webhook/grafana-alerts-3f9c1a7e5b
```

A 200 plus an updated `last_triggered` on
`automation.grafana_alert_notification` means the path is intact.

### Two traps met while building this

- Grafana **refuses to start** if an alert rule sets `__dashboardUid__` without
  `__panelId__`. It fails the whole provisioning module, so a typo in an
  annotation takes Grafana down rather than skipping one rule.
- The disk rules use `noDataState = "OK"`. With the `NoData` default they fire
  on every Grafana restart, because the first evaluation sees an empty window.
  `gmktec-exporter-down` carries the genuine "the host went away" case instead.

## Playback

Jellyfin on gmktec, <http://192.168.0.51:8096>, reading `/data/media`
read-only. It is a second Jellyfin — the one on trigkey serves the Garage
`guitar` bucket over rclone and is unrelated. They share a port number but not
a host.

The alternative, one Jellyfin on trigkey with `/data` over NFS, was rejected:
it would push every stream across the LAN twice and add a mount that can hang.

First run needs the setup wizard by hand — an account and a library are state,
not config:

1. Create the admin account.
2. Add library **Shows** → `/data/media/tv`.
3. Add library **Movies** → `/data/media/movies`.

VAAPI transcoding on the Vega iGPU is available; the drivers and the
`/dev/dri/renderD128` access are declared in the module, but the switch is in
Jellyfin's dashboard under Playback → Transcoding. Most files direct-play, so
this only matters for clients that cannot handle x265.

`/var/lib/jellyfin` is **not** backed up. Watch progress and accounts are the
only things a reinstall loses.
