# Plan 004: SSH to trigkey over the tailnet uses the managed authorized_keys, not Tailscale identity

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 2625ad7..HEAD -- hosts/nixos/optional/tailscale.nix hosts/nixos/trigkey/default.nix`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S (about 20 minutes)
- **Risk**: LOW (plain OpenSSH over the tailnet is already allowed)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `2625ad7`, 2026-11-24

## Why this matters

`tailscale up --ssh` makes Tailscale answer SSH on the tailnet address and log
people in by tailnet identity, bypassing the `authorized_keys` list the repo
manages with care (it even documents how to revoke the iPhone key). On trigkey,
`eric` has passwordless sudo, so any tailnet device or identity that the
(un-versioned) Tailscale ACL allows to SSH as eric gets root on the main
server — including a stolen, still-logged-in laptop or phone. Removing `--ssh`
keeps tailnet SSH working through OpenSSH and the managed keys.

## Current state

`hosts/nixos/optional/tailscale.nix` (imported only by trigkey; gmktec does not import it — see `hosts/nixos/gmktec/default.nix:42`):
```nix
# tailscale.nix:9
# --ssh           lets `ssh eric@trigkey` work via Tailscale identity (no key prompt)
# tailscale.nix:14-21
services.tailscale = {
  enable = true;
  openFirewall = true; # allows UDP 41641 for direct (non-relay) connections
  authKeyFile = config.sops.secrets."tailscale/authkey".path;
  extraUpFlags = [
    "--ssh"
    "--accept-dns=false"
  ];
};
```
`hosts/nixos/trigkey/default.nix:53-58` already admits OpenSSH on the tailnet:
```nix
services.openssh.openFirewall = false;
networking.firewall.extraInputRules = ''
  ip saddr 192.168.0.0/24 tcp dport 22 accept comment "ssh from LAN"
  iifname "tailscale0" tcp dport 22 accept comment "ssh from tailnet"
'';
```
`trigkey/default.nix:65`: `security.sudo.wheelNeedsPassword = false;` (documented trade-off — do not change it).

Important NixOS detail: `extraUpFlags` is applied by the `tailscaled-autoconnect` unit only on first login. Removing the flag from Nix does **not** turn Tailscale SSH off on an already-logged-in node. The live setting must be changed with `sudo tailscale set --ssh=false`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build trigkey | `nix build .#nixosConfigurations.trigkey.config.system.build.toplevel --no-link` | exit 0 |
| Live state | `tailscale debug prefs \| grep -i runssh` | `"RunSSH": false` after the change |
| Deploy (operator) | `nh os switch .` | exit 0 |

## Scope

**In scope**: `hosts/nixos/optional/tailscale.nix`; `docs/services/tailscale.md` if it mentions Tailscale SSH.

**Out of scope**: sudo policy, OpenSSH settings, the Tailscale ACL (lives in the Tailscale admin console, not this repo), other hosts.

## Git workflow

Commit on `main`, push. Message: `fix(tailscale): drop tailscale ssh; tailnet ssh goes through openssh keys`.

## Steps

### Step 1: Confirm the client keys work over plain SSH first

From a device that uses tailnet SSH today (operator), run `ssh -o PreferredAuthentications=publickey eric@<trigkey tailnet name or 100.x address> true`.
- If it fails with "Permission denied (publickey)", that device has no key in `authorized_keys`. STOP: the operator must add its public key to `hosts/nixos/common` or `trigkey/default.nix` first, or they lose tailnet access from that device.

Note: while `--ssh` is on, Tailscale intercepts port 22 on the tailnet address, so this test may succeed through Tailscale. To test OpenSSH alone, the operator runs this from the LAN against `192.168.0.202` with the same client key.

### Step 2: Remove the flag from Nix

Delete `"--ssh"` from `extraUpFlags` and replace the comment on line 9 with one explaining that tailnet SSH goes through OpenSSH and the managed `authorized_keys`, because Tailscale SSH bypasses that list and `eric` has passwordless sudo on trigkey.

**Verify**: trigkey build → exit 0; `grep -n -- '"--ssh"' hosts/nixos/optional/tailscale.nix` → no output.

### Step 3: Turn it off on the live node (operator)

1. `nh os switch .`
2. `sudo tailscale set --ssh=false`
3. `tailscale debug prefs | grep -i runssh` → `"RunSSH": false`

### Step 4: Re-test

From a tailnet device: `ssh eric@<trigkey tailnet address> true` → succeeds via key (it may now prompt for the key's passphrase/agent, which is expected).

## Done criteria

- [ ] trigkey builds; `"--ssh"` not in `tailscale.nix`
- [ ] `tailscale debug prefs | grep -i runssh` on trigkey → `"RunSSH": false`
- [ ] tailnet SSH with a key still works
- [ ] `plans/README.md` status row updated

## STOP conditions

- Step 1 shows a device relies on Tailscale identity and has no SSH key.
- `tailscale set --ssh=false` is not a recognised flag on the installed version (`tailscale version`): report the version instead of improvising.
- The E.T. iOS app or etd relies on Tailscale SSH (check `docs/` for "tailscale ssh"); etd is iroh-based and should not, but if docs say otherwise, STOP.

## Maintenance notes

- If Tailscale SSH is wanted again later, enable it with `check` mode and a narrow, version-controlled ACL `ssh` rule; do not re-add the bare flag.
- Deferred (separate finding, not this plan): one trigkey SSH key has root on every host; per-target deploy keys are a larger change.
