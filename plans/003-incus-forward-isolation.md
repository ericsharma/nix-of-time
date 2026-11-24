# Plan 003: The docker-services LXC can reach the internet but not the LAN, tailnet or wg-pangolin

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 2625ad7..HEAD -- hosts/nixos/optional/incus.nix hosts/nixos/docker-services/`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S (about 1 hour including the live tests)
- **Risk**: MED (a wrong rule cuts the LXC's internet; easy rollback)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `2625ad7`, 2026-11-24

## Why this matters

The LXC at 10.0.100.10 runs internet-facing containers (Karakeep, Dawarich,
Rybbit, Koito, Endurain, Cobalt). trigkey already blocks it from trigkey's own
ports. But the forward chain accepts **everything** from `incusbr0`, and Incus
NATs it, so the LXC reaches the whole LAN as trigkey (192.168.0.202). gmktec
admits 192.168.0.0/24 to SABnzbd, Sonarr, Radarr, Prowlarr and Chaptarr, and
SABnzbd has no login. A compromised container can therefore drive the download
stack and probe every LAN device. After this plan it can only reach the internet.

## Current state

`hosts/nixos/optional/incus.nix` (imported by trigkey only):
```nix
# incus.nix:19-30
# The LXC gets DHCP and DNS from Incus's dnsmasq on the bridge, and nothing
# else on this host. Not trustedInterfaces: that let the LXC, which runs
# internet-facing containers, reach every port on trigkey (Postgres,
# garage-webui, Syncthing). trigkey's own connections into the LXC (Newt,
# Prometheus, rebuild-docker) are outbound and need no rule.
networking.firewall.interfaces.incusbr0 = { allowedUDPPorts = [ 53 67 ]; allowedTCPPorts = [ 53 ]; };

# incus.nix:33-36
# Allow forwarded traffic to/from Incus containers
networking.firewall.extraForwardRules = ''
  iifname "incusbr0" accept
  oifname "incusbr0" accept
'';
```
- Bridge: `incusbr0`, `ipv4.address = 10.0.100.1/24`, `ipv4.nat = true` (lines 40–50).
- nftables is enabled (`networking.nftables.enable = true`, line 13), so `extraForwardRules` is nftables syntax inside the NixOS `filter forward` chain.
- Private ranges in this fleet: LAN `192.168.0.0/24`, tailnet `100.64.0.0/10`, wg-pangolin `10.100.0.0/24` (`hosts/nixos/optional/wg-pangolin.nix`), bridge itself `10.0.100.0/24`.
- `grep -rn '192\.168\.\|100\.6[4-9]\|10\.100\.' hosts/nixos/docker-services` (run at planning time) found no LXC service that targets a LAN, tailnet or wg address. trigkey → LXC traffic (Newt, Prometheus, SSH for `rebuild-docker`) is not forwarded traffic (it originates on trigkey), so the forward chain does not affect it.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Format | `nix fmt -- --check .` | exit 0 |
| Build trigkey | `nix build .#nixosConfigurations.trigkey.config.system.build.toplevel --no-link` | exit 0 |
| Live ruleset | `sudo nft list chain inet nixos-fw forward` | shows the new rules |
| From the LXC | `ssh root@10.0.100.10 '<cmd>'` | — |
| Deploy (operator) | `nh os switch .` | exit 0 |
| Rollback | `sudo nixos-rebuild switch --rollback` | previous rules back |

## Scope

**In scope**: `hosts/nixos/optional/incus.nix` (the `extraForwardRules` block and its comment), `docs/fleet/trigkey.md` only if it describes LXC network access.

**Out of scope**: the `incusbr0` input rules (lines 19–30); gmktec firewall rules; Docker port bindings inside the LXC; Tailscale config.

## Git workflow

Commit on `main`, push. Message: `fix(incus): stop the LXC from reaching the LAN, tailnet and wg-pangolin`.

## Steps

### Step 1: Baseline from inside the LXC (before the change)

Run and record the output:
```sh
ssh root@10.0.100.10 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 https://cache.nixos.org/nix-cache-info'
ssh root@10.0.100.10 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 http://192.168.0.51:8080/ || echo blocked'
```
Expected: first `200`; second returns an HTTP code (proves the LAN is reachable today). If the second already says `blocked`, STOP and report: the finding does not reproduce.

### Step 2: Replace the forward rules

Replace the block with (keep a why-comment in the repo's style):
```nix
# Forwarded traffic for the LXC. Replies to anything are allowed. New
# connections from the LXC may go to the internet only: it runs
# internet-facing containers, and with NAT it would otherwise reach every
# LAN device as trigkey (gmktec admits the LAN to SABnzbd, which has no login).
networking.firewall.extraForwardRules = ''
  ct state established,related accept
  iifname "incusbr0" ip daddr { 192.168.0.0/16, 172.16.0.0/12, 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16 } drop comment "LXC must not reach private nets"
  iifname "incusbr0" accept
  oifname "incusbr0" ct state new drop comment "nothing initiates into the LXC through the forward path"
'';
```
Note: 10.0.0.0/8 also covers the bridge itself, which is fine — LXC-to-LXC traffic on the same bridge is bridged, not forwarded.

**Verify**: trigkey build → exit 0.

### Step 3: Deploy and re-test (operator runs the deploy)

After `nh os switch .`:
```sh
ssh root@10.0.100.10 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 https://cache.nixos.org/nix-cache-info'   # → 200
ssh root@10.0.100.10 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 http://192.168.0.51:8080/ || echo blocked' # → 000 then blocked
ssh root@10.0.100.10 'curl -s -o /dev/null -w "%{http_code}\n" -m 5 http://10.100.0.11:3004/ || echo blocked'  # → blocked
curl -s -o /dev/null -w "%{http_code}\n" http://10.0.100.10:3088/   # from trigkey, Karakeep → 200 or 30x
ssh root@10.0.100.10 'docker ps --format "{{.Names}} {{.Status}}"'   # all Up
```
Then confirm one public site still loads through Pangolin (Newt on trigkey dials the LXC): open the Karakeep public URL from a phone off Wi-Fi.

### Step 4: Rebuild-docker still works

`rebuild-docker` (operator) → exits 0. It needs the LXC to fetch from cache.nixos.org, which Step 3 already proved.

## Test plan

Step 1 and Step 3 are the tests. Record their outputs in the commit body.

## Done criteria

- [ ] `nix fmt -- --check .` exits 0; trigkey builds
- [ ] `sudo nft list chain inet nixos-fw forward | grep -c 'LXC must not reach private nets'` → 1
- [ ] Step 3 expected outputs all match
- [ ] `plans/README.md` status row updated

## STOP conditions

- Step 1's LAN probe is already blocked.
- The chain name differs (`sudo nft list tables` does not show `inet nixos-fw`) — the rule text may need adapting; report instead of guessing.
- After deploy, any LXC container is not `Up`, the internet probe fails, or a public site through Pangolin fails → `sudo nixos-rebuild switch --rollback`, then report.
- An LXC service turns out to need a LAN destination (for example the local LLM at 192.168.0.5): report it; the fix is a narrow `accept` for that one host:port before the drop line, and the owner decides.

## Maintenance notes

- A future LXC service that needs a LAN service must get an explicit, single host:port accept above the drop line, with a comment.
- If Incus ever moves to IPv6 on the bridge (`ipv6.address` is `none` today), add the equivalent `ip6 daddr` drop.
