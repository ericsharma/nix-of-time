# Usenet stack (gmktec)

SABnzbd downloads and extracts. Prowlarr manages the indexer and hands
`.nzb` files to SABnzbd. Both run natively on gmktec (`192.168.0.51`).

| Piece | Port | Module |
|-------|------|--------|
| SABnzbd | 8080 (LAN) | `hosts/nixos/gmktec/sabnzbd.nix` |
| Prowlarr | 9696 (LAN) | `hosts/nixos/gmktec/prowlarr.nix` |
| Sonarr | 8989 (LAN) | `hosts/nixos/gmktec/sonarr.nix` |
| Radarr | 7878 (LAN) | `hosts/nixos/gmktec/radarr.nix` |
| `/data` tree + `media` group | — | `hosts/nixos/gmktec/media-storage.nix` |
| shared reconcile helpers | — | `hosts/nixos/gmktec/servarr-api.nix` |

- <http://192.168.0.51:8080>
- <http://192.168.0.51:9696>
- <http://192.168.0.51:8989>
- <http://192.168.0.51:7878>

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
ssh eric@192.168.0.51 'sudo systemctl restart sabnzbd'
```

A changed secret does **not** restart its consumer on its own — restart it.

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
