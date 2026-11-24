# Plan 002: Backups survive the house, a compromised trigkey, and gmktec's NVMe

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 2625ad7..HEAD -- hosts/nixos/trigkey/backup.nix hosts/nixos/gmktec/ docs/services/backup.md docs/fleet/gmktec.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M (about half a day, plus the first upload of ~150 GB)
- **Risk**: LOW (adds jobs; the existing repository and schedule do not change)
- **Depends on**: none. Plan 001 is nice to have first: its staleness alert then covers the new jobs (add them to its job list).
- **Category**: bug (data-loss risk)
- **Planned at**: commit `2625ad7`, 2026-11-24

## Why this matters

Every backup is in one restic repository on one Samsung T7 attached to gmktec,
in the same house as trigkey. `appendOnly = false`, and trigkey holds the
credentials that run `forget --prune`, so root on trigkey (an attacker or a
mistake) can delete every snapshot. A fire or theft loses everything,
Vaultwarden included. Separately, nothing on gmktec is backed up: Papra's
uploaded documents exist nowhere else, and the *arr/Jellyfin/Seerr databases
would have to be rebuilt by hand. One small trigkey path,
`/var/lib/options-ledger-server` (holds `portfolio.local.json`, copied there by
hand), is in no backup job and has no "not backed up because" note.

## Current state

- `hosts/nixos/trigkey/backup.nix`
  - Lines 9–13: one repository (`restic/repository` sops secret = REST URL on gmktec:8000), password `restic/password`.
  - Lines 33–49: `common` (repositoryFile, passwordFile, `initialize = true`, `--one-file-system --exclude-caches`) and `retention` (`--group-by host,paths --keep-daily 7 --keep-weekly 4 --keep-monthly 6`).
  - Jobs: `databases` 01:30, `lxc-databases` 01:40, `immich` 02:00, `garage` 03:00, `docker-services` 04:00, `system-state` 04:30 (only this one prunes and runs `restic check --read-data-subset=2%`).
  - Lines 208–235 `system-state.paths` — `/var/lib/options-ledger-server` is absent. `/srv/komodo` (line 229) is handled by plan 005, not here.
  - Lines 253–257: "Deliberately not backed up" comment list.
- `hosts/nixos/gmktec/backup-server.nix` — `services.restic.server` on the T7 (`/mnt/backup/restic`), `appendOnly = false` with a comment explaining why (lines 36–46). Firewall admits 192.168.0.202 (trigkey) only.
- gmktec state with no backup (each path is documented in its module):
  - `/srv/papra/app-data` — SQLite + uploaded documents (`gmktec/papra.nix:5`); owned by uid 999.
  - `/var/lib/sonarr`, `/var/lib/radarr`, `/var/lib/prowlarr` (SQLite), `/var/lib/jellyfin` (metadata, users, watch state), `/var/lib/jellyseerr/config`, `/srv/chaptarr/config` (SQLite).
  - Not wanted: `/data` (media; re-downloadable).
- `hosts/nixos/optional/options-ledger.nix:124-126` — `PORTFOLIO_DATA_PATH = "/var/lib/options-ledger-server/portfolio.local.json"`, `StateDirectory = "options-ledger-server"`.
- `docs/services/backup.md:105` says "Nothing on gmktec itself is backed up"; `:110-111` lists the decisions "Append-only is off" and "one disk, no off-site copy".
- Repo conventions: sops scalars `service/<name>` in `secrets/secrets.yaml`, declared in the module with `sops.secrets."service/name" = { };`. Why-comments in modules. Docs: one home per fact (`docs/services/backup.md` is the home for backup behaviour).

## Operator decision required before Step 2

Off-site provider. **Recommended: Backblaze B2** (≈ $6/TB/month; ~150 GB ≈ $1/month). B2 application keys can be created **without `deleteFiles`**: then a delete only *hides* a file, and a bucket lifecycle rule keeps hidden versions for 30 days. That makes the off-site copy undeletable from trigkey for 30 days, which is the property we want. Alternative: Cloudflare R2 (no egress fees, but no equivalent no-delete key; would need object lock).

If the executor cannot find the secrets listed in Step 2, STOP and hand the operator this checklist:
1. Create B2 bucket `nix-of-time-restic` (private), with lifecycle "keep prior versions 30 days".
2. Create an application key restricted to that bucket, capabilities `listBuckets, listFiles, readFiles, writeFiles` (no `deleteFiles`).
3. `sops secrets/secrets.yaml` and add:
   - `restic-offsite/env: |` with lines `B2_ACCOUNT_ID=…` and `B2_ACCOUNT_KEY=…`
   - `restic-offsite/password: <new random password, different from restic/password>`
   - Store the password a second way that does not depend on trigkey (not Vaultwarden on trigkey).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Format | `nix fmt -- --check .` | exit 0 |
| Eval | `nix flake check --no-build` | exit 0 |
| Build trigkey | `nix build .#nixosConfigurations.trigkey.config.system.build.toplevel --no-link` | exit 0 |
| Build gmktec | `nix build .#nixosConfigurations.gmktec.config.system.build.toplevel --no-link` | exit 0 |
| Secret exists | `sops -d --extract '["restic-offsite"]["password"]' secrets/secrets.yaml >/dev/null && echo ok` | `ok` (never print the value) |
| Deploy (operator) | `nh os switch .` on trigkey; gmktec: `nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo` | exit 0 |

## Scope

**In scope**:
- `hosts/nixos/trigkey/backup.nix`
- `hosts/nixos/gmktec/backup-client.nix` (create) and its import line in `hosts/nixos/gmktec/default.nix`
- `docs/services/backup.md`, `docs/fleet/gmktec.md` (update the "nothing on gmktec is backed up" facts)

**Out of scope**:
- `hosts/nixos/gmktec/backup-server.nix` — leave `appendOnly = false`; the off-site no-delete key replaces that hardening.
- Retention values, existing job schedules, `/srv/komodo` (plan 005).
- `secrets/secrets.yaml` values — the operator edits them; the executor never prints or writes secret values.

## Git workflow

- Commit on `main`, push after each commit. Conventional commits, e.g. `feat(backup): copy restic repo off-site to B2`.

## Steps

### Step 1: Back up options-ledger's state on trigkey

Add `"/var/lib/options-ledger-server"` to `system-state.paths` in `backup.nix`, with a comment: holds `portfolio.local.json`, copied there by hand; no other server-side copy.

**Verify**: trigkey build → exit 0; `grep -n options-ledger-server hosts/nixos/trigkey/backup.nix` → one line.

### Step 2: Off-site copy of the trigkey repository

Confirm secrets with the "Secret exists" command for both `restic-offsite/password` and `restic-offsite/env`. If either fails, STOP (see operator checklist).

In `backup.nix`:
- `sops.secrets."restic-offsite/env" = { };` and `sops.secrets."restic-offsite/password" = { };`
- A systemd service `restic-offsite-copy` + timer at `06:00` (`Persistent = true`), after `restic-backups-system-state.service` finishes its 04:30 run. Service: `Type = oneshot`, `EnvironmentFile = config.sops.secrets."restic-offsite/env".path`, script:
  ```sh
  export RESTIC_REPOSITORY=b2:nix-of-time-restic:trigkey
  export RESTIC_PASSWORD_FILE=${config.sops.secrets."restic-offsite/password".path}
  # First run only: create the off-site repo with the same chunker params, so
  # `copy` reuses blocks instead of re-uploading. Source repo opened via --from-*.
  restic cat config >/dev/null 2>&1 || restic init \
    --from-repository-file ${repositoryFile} --from-password-file ${passwordFile} --copy-chunker-params
  restic copy --from-repository-file ${repositoryFile} --from-password-file ${passwordFile}
  ```
  Use `${pkgs.restic}/bin/restic`. Add a header comment: why (off-site, key cannot delete, hidden versions kept 30 days by bucket lifecycle), and that there is deliberately **no** `forget`/`prune` against this repo — the key cannot delete. Repo growth is bounded by the source repo's retention only once a manual prune is done with a full-access key (document that in `docs/services/backup.md`).
- Do not touch `common`, `retention` or any existing job.

Check `restic copy` flag names against the packaged version: `nix shell nixpkgs#restic -c restic copy --help | grep -E 'from-repository-file|from-password-file'` → both present. If not, STOP.

**Verify**: trigkey build → exit 0.

### Step 3: Back up gmktec's stateful services off gmktec

Create `hosts/nixos/gmktec/backup-client.nix` with `services.restic.backups.gmktec-state`:
- repository: `b2:nix-of-time-restic:gmktec`, `environmentFile` and `passwordFile` from the same `restic-offsite/*` secrets (declare them in this module; gmktec decrypts `secrets.yaml` too). `initialize = true`.
- paths: the 7 paths listed in "Current state".
- `backupPrepareCommand`: for each SQLite DB, write a consistent copy with `${pkgs.sqlite}/bin/sqlite3 <db> ".backup '/var/backup/gmktec-sqlite/<svc>.db'"` (create that dir first with `install -d -m 0700`). Never write the copy into the service's own directory. Add `/var/backup/gmktec-sqlite` to `paths`. Find each DB file with `sudo ls /var/lib/sonarr /var/lib/radarr /var/lib/prowlarr /srv/chaptarr/config /var/lib/jellyseerr/config/db /srv/papra/app-data` on gmktec (read-only) and list the exact files in the plan's code; if a path does not exist, STOP.
- timerConfig `OnCalendar = "03:30"`, `Persistent = true`.
- No prune (same reason as Step 2).
- Header comment: what is covered and why `/data` is not.

Add `./backup-client.nix` to the imports in `hosts/nixos/gmktec/default.nix` next to `./backup-server.nix`, with a short comment.

**Verify**: gmktec build → exit 0.

### Step 4: Docs

In `docs/services/backup.md`: add the off-site repo (provider, bucket, what writes to it, no delete capability, lifecycle 30 days, how to restore from it: `RESTIC_REPOSITORY=b2:nix-of-time-restic:trigkey restic snapshots`), replace "One disk, no off-site copy" and "Nothing on gmktec itself is backed up". In `docs/fleet/gmktec.md`, change the storage-rules line that says nothing is backed up to a link to `docs/services/backup.md`.

**Verify**: `grep -n 'Nothing on gmktec' docs/services/backup.md docs/fleet/gmktec.md` → no matches.

### Step 5: Deploy and first run (operator)

1. Deploy trigkey and gmktec.
2. `sudo systemctl start restic-offsite-copy` on trigkey (first upload ~150 GB; run it in the evening).
3. `sudo systemctl start restic-backups-gmktec-state` on gmktec.

## Test plan

- After Step 5: `sudo systemctl status restic-offsite-copy` → `status=0/SUCCESS`.
- Restore drill (operator, 10 min): on any host, `restic -r b2:nix-of-time-restic:trigkey snapshots` lists the same snapshot IDs as the T7 repo; `restic restore latest --target /tmp/r --include /var/lib/vaultwarden` succeeds.
- Delete test: with the B2 key, `restic -r b2:… forget <one snapshot id>` must **fail** with a permission error. If it succeeds, the key has `deleteFiles` — STOP and report.

## Done criteria

- [ ] `nix fmt -- --check .` and `nix flake check --no-build` exit 0
- [ ] trigkey and gmktec toplevels build
- [ ] `grep -n options-ledger-server hosts/nixos/trigkey/backup.nix` → 1 match
- [ ] After deploy: `systemctl list-timers restic-offsite-copy.timer` (trigkey) and `restic-backups-gmktec-state.timer` (gmktec) both listed
- [ ] Delete test above fails as expected
- [ ] `plans/README.md` status row updated

## STOP conditions

- Off-site secrets missing (hand the operator the checklist).
- `restic copy` flags differ from the plan.
- A gmktec state path or DB file does not exist.
- The B2 key can delete (delete test succeeds).
- The first copy fails with a chunker/params error.

## Maintenance notes

- New stateful services on gmktec must be added to `backup-client.nix` paths.
- The off-site repo is never pruned by automation. Review its size twice a year; prune by hand with a separate full-access key that is not stored on any host.
- If plan 001 has landed, add `gmktec-state` (on gmktec) and the copy job to its stale-backup alert.
