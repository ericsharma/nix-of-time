# Plan 005: Units fail visibly instead of looking green while broken

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 2625ad7..HEAD -- hosts/nixos/trigkey/containers.nix hosts/nixos/optional/whisper-transcription.nix hosts/nixos/optional/eternatv-sidecar.nix hosts/nixos/optional/pirousync.nix hosts/nixos/optional/options-ledger.nix hosts/nixos/optional/pgweb.nix hosts/nixos/optional/monitoring.nix hosts/nixos/gmktec/sabnzbd.nix hosts/nixos/gmktec/sonarr.nix hosts/nixos/gmktec/radarr.nix hosts/nixos/gmktec/chaptarr.nix hosts/nixos/gmktec/proton-vpn.nix hosts/nixos/docker-services/services/ hosts/nixos/trigkey/backup.nix`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S (about 1.5 hours; six small independent fixes)
- **Risk**: LOW
- **Depends on**: none. Lands best before or with plan 001 (its failed-unit alert then sees these failures).
- **Category**: bug
- **Planned at**: commit `2625ad7`, 2026-11-24

## Why this matters

Six small defects share one effect: something breaks and systemd still shows
it as fine, or a rule silently does nothing. Each fix is a few lines. Each
part below is independent — do them in order, one commit each, and build
after each.

## Current state, per part

**A. LXC launcher swallows start failures** — `hosts/nixos/trigkey/containers.nix:16-31`:
```nix
"incus-${name}" = {
  after = [ "incus.service" "incus-preseed.service" ];
  ...
  script = ''
    if ! ${incus} info ${name} &>/dev/null; then
      ${incus} launch ${image} ${name} ${extraArgs}
    else
      ${incus} start ${name} 2>/dev/null || true
    fi
```
`incus start` on a running instance exits non-zero ("already running"), which is why `|| true` exists. It also hides a real failure. The unit also does not order after `incus-default-profile.service` (defined in `hosts/nixos/optional/incus.nix:62`), which adds the root disk and NIC `incus launch` needs.

**B. tmpfiles path with a space is dropped** — `hosts/nixos/optional/whisper-transcription.nix:169`:
```nix
"d /srv/obsidian/Brain 2.0/Transcriptions  0755 eric users -"
```
Correct quoting in this repo: `hosts/nixos/optional/syncthing.nix:44` → `"d '/srv/obsidian/Brain 2.0' 0755 eric users -"`.

**C. Postgres clients order on the server, not on role/DB creation** — on this nixpkgs, `ensureUsers`/`ensureDatabases` run in `postgresql-setup.service`; `postgresql.target` is reached after it (verified live: both units and the target exist). These order only on `postgresql.service`:
- `hosts/nixos/optional/eternatv-sidecar.nix:52-56` (after+requires) and `:89-90` (prune oneshot)
- `hosts/nixos/optional/pirousync.nix:116-120`
- `hosts/nixos/optional/options-ledger.nix:114-117` (after only, no requires)
- `hosts/nixos/optional/pgweb.nix:41-42`
Exemplar done right: `hosts/nixos/trigkey/pangolin-db.nix:52-53` uses `postgresql-setup.service`.

**D. DB health waits never time out** — `oci-containers` sets `TimeoutStartSec = 0` for container units, so these `preStart` loops can hang forever in "activating":
- `hosts/nixos/docker-services/services/koito.nix:37`
- `rybbit.nix:114,117,124`
- `dawarich.nix:131,134,141`
- `endurain.nix:102`
Pattern today (`koito.nix:36-40`):
```nix
systemd.services.docker-koito.preStart = ''
  until docker inspect --format '{{.State.Health.Status}}' koito-db 2>/dev/null | grep -q "healthy"; do
    sleep 2
  done
'';
```

**E. Dead dependency on `sops-nix.service`** — sops-nix runs as an activation script here; `systemctl cat sops-nix.service` → "No files found". References:
- `hosts/nixos/optional/monitoring.nix:877-878` (after + wants)
- `hosts/nixos/gmktec/sabnzbd.nix:279`, `sonarr.nix:95`, `radarr.nix:94`, `chaptarr.nix:156`, `proton-vpn.nix:39` (after)

**F. Backup of a removed service** — `hosts/nixos/trigkey/backup.nix:229`: `"/srv/komodo"` in `system-state.paths`. No module references Komodo; `/srv/komodo` (3.8 MB of old MongoDB files) is still on disk.

Conventions: why-comments in modules; conventional commits; `nix fmt`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Format | `nix fmt -- --check .` | exit 0 |
| Eval all | `nix flake check --no-build` | exit 0 |
| Build host | `nix build .#nixosConfigurations.<trigkey\|gmktec\|docker-services>.config.system.build.toplevel --no-link` | exit 0 |
| Deploy (operator) | trigkey `nh os switch .`; LXC `rebuild-docker`; gmktec `nixos-rebuild switch --flake .#gmktec --target-host eric@192.168.0.51 --sudo` | exit 0 |

## Scope

**In scope**: exactly the files listed in "Current state" A–F.

**Out of scope**: deleting `/srv/komodo` on disk (owner's call); container image tags; docker network creation order (separate, lower-value finding); anything else in these files.

## Git workflow

Commit on `main`, push after each part. Messages like `fix(incus): fail the launcher unit when the LXC does not start`.

## Steps

### Step A: Make the LXC launcher fail loudly

In `containers.nix`:
1. Add `"incus-default-profile.service"` to `after`, and add `requires = [ "incus.service" "incus-default-profile.service" ];`.
2. Replace the `else` branch with a status check:
   ```sh
   elif [ "$(${incus} list ${name} -c s -f csv)" != "RUNNING" ]; then
     ${incus} start ${name}
   fi
   ```
   (restructure the `if` accordingly; keep `launch` for the not-exists case). Comment: `incus start` errors on a running instance, so check state instead of discarding errors.

**Verify**: trigkey build → exit 0; `grep -n '|| true' hosts/nixos/trigkey/containers.nix` → no match on the start line.

### Step B: Quote the tmpfiles path

Change line 169 to `"d '/srv/obsidian/Brain 2.0/Transcriptions' 0755 eric users -"`.

**Verify**: trigkey build → exit 0. After deploy: `sudo systemd-tmpfiles --create 2>&1 | grep -i brain` → no output.

### Step C: Order Postgres clients on `postgresql.target`

In each listed unit, replace `"postgresql.service"` with `"postgresql.target"` in `after`, and in `requires` (add `requires = [ "postgresql.target" ];` to options-ledger, which lacks it). Do not change `pangolin-db.nix` or `pirousync-dev.nix`.

Check the target exists in the built config first: `nix eval --raw .#nixosConfigurations.trigkey.config.systemd.targets.postgresql.description` → prints a string. If it errors, use `postgresql-setup.service` instead (as `pangolin-db.nix` does).

**Verify**: trigkey build → exit 0; `grep -n '"postgresql.service"' hosts/nixos/optional/{eternatv-sidecar,pirousync,options-ledger,pgweb}.nix` → no output.

### Step D: Bound the health waits

Replace every `until …; do sleep 2; done` listed above with a bounded loop (5 minutes):
```sh
for i in $(seq 1 150); do
  docker inspect --format '{{.State.Health.Status}}' koito-db 2>/dev/null | grep -q healthy && break
  [ "$i" = 150 ] && { echo "koito-db not healthy after 5 min" >&2; exit 1; }
  sleep 2
done
```
Keep the container name per loop. In `endurain.nix:100+` the loop iterates over `$c`; wrap the same bound inside its `for c in …` loop. Add one comment per file: oci-containers sets `TimeoutStartSec=0`, so an unbounded wait would never fail.

**Verify**: docker-services build → exit 0; `grep -c 'until docker inspect' hosts/nixos/docker-services/services/*.nix` → all `0`.

### Step E: Remove the dead `sops-nix.service` edges

Delete those `after`/`wants` entries (if `after` becomes empty, remove the attribute). No replacement: secrets are decrypted during activation, before units start.

**Verify**: `grep -rn 'sops-nix.service' hosts` → no output; trigkey and gmktec build → exit 0.

### Step F: Stop backing up Komodo leftovers

Remove `"/srv/komodo"` from `system-state.paths`. Existing snapshots keep the data for 6 months under retention. Add to the "Deliberately not backed up" comment block: `/srv/komodo  leftovers of a removed service; in snapshots until <date + 6 months>`.

**Verify**: `grep -n komodo hosts/nixos/trigkey/backup.nix` → only the comment line; trigkey build → exit 0.

## Test plan

- After deploying trigkey: `systemctl status incus-docker-services` → `active (exited)`, `status=0/SUCCESS`; `sudo incus list docker-services -c s -f csv` → `RUNNING`.
- `systemctl list-dependencies --after eternatv-sidecar.service | grep postgresql` → shows `postgresql.target`.
- After `rebuild-docker`: `ssh root@10.0.100.10 'docker ps --format "{{.Names}} {{.Status}}"'` → all `Up`.
- After gmktec deploy: `systemctl status sabnzbd sonarr radarr` → running.

## Done criteria

- [ ] `nix fmt -- --check .`, `nix flake check --no-build` exit 0
- [ ] trigkey, gmktec, docker-services build
- [ ] `grep -rn 'sops-nix.service' hosts` → no output
- [ ] `grep -c 'until docker inspect' hosts/nixos/docker-services/services/*.nix` → all 0
- [ ] Test plan checks pass after deploy
- [ ] `plans/README.md` status row updated

## STOP conditions

- Any excerpt above does not match the file.
- `incus list -c s -f csv` prints something other than `RUNNING`/`STOPPED` for the instance (format changed): report the output.
- After deploy, the LXC is not RUNNING or any LXC container is not Up → roll back (`sudo nixos-rebuild switch --rollback` on trigkey; `rebuild-docker` from the previous commit for the LXC) and report.
- A Postgres client fails to start after Step C.

## Maintenance notes

- New Postgres consumers: order on `postgresql.target`, not `postgresql.service`.
- New docker-services stacks: copy the bounded wait loop, not the old `until` loop.
- Deferred: each docker network is created in one container's preStart only (rybbit, karakeep, endurain, dawarich), which races on a fresh LXC. Fix with a per-stack network oneshot; low value because it only bites on first boot.
