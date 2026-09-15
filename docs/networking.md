# Networking and exposure

Nothing listens on a public port. Services bind to loopback, public traffic arrives through an outbound tunnel, and LAN access is opened one port at a time.

## Pick an exposure tier

| Tier | How | Use when |
|------|-----|----------|
| **Loopback** (default) | Bind `127.0.0.1`, no firewall rule | Always, unless you have a stated reason |
| **LAN** | A `*.local` alias, or a firewall rule scoped to `192.168.0.0/24` | Useful from a phone or laptop at home, and safe without a login |
| **Public** | A Pangolin route to a loopback port. Never a firewall rule. | Needed away from home |

Move a service up a tier only with a reason. A LAN port on a service with no login is a decision, not a default.

## Public: Newt and Pangolin

To publish a service:

1. Confirm it binds `127.0.0.1`.
2. In the Pangolin dashboard, route `<name>.ericsharma.xyz` to `127.0.0.1:<port>` through that host's Newt.

No NixOS change is needed. Newt dials out to `https://pangolin.ericsharma.xyz`, so no inbound port is open and nothing is forwarded on the router.

| Host | Newt module | sops secret |
|------|-------------|-------------|
| trigkey | `hosts/nixos/trigkey/newt.nix` | `newt/env` |
| gmktec | `hosts/nixos/gmktec/newt.nix` | `newt-gmktec/env` |

**Never publish a service that has no login.** SABnzbd, Prowlarr, Sonarr, Radarr, Ladder, and FlareSolverr have none. The only thing keeping them private is that no Pangolin route exists.

### Known public routes

| Name | Serves |
|------|--------|
| `pangolin.ericsharma.xyz` | Pangolin control plane |
| `radio.ericsharma.xyz` | Icecast, port 8000 |
| `video.ericsharma.xyz` | EternaTV, port 8088 |
| `vault.ericsharma.xyz` | Vaultwarden |
| `d.ericsharma.xyz` | Dawarich |
| `tracking.ericsharma.xyz` | Rybbit |
| `options.ericsharma.xyz` | Options Ledger |
| `bellewatsonstudio.com` | Belle Watson Studios |
| `ericsharma.xyz` | Personal site |

The Pangolin dashboard is the source of truth. This table drifts.

## Firewall

Both hosts start with only port 22 open. Each module opens what it needs.

**trigkey** uses `allowedTCPPorts` / `allowedUDPPorts`, which open on every interface:

| Port | Service |
|------|---------|
| 22 | SSH |
| 3030 | Dawarich nginx proxy |
| 3900 | Garage S3 API |
| 5757 | Unknown. Set in `hosts/nixos/trigkey/default.nix` with no comment. Identify it before removing it. |
| 8096 | Jellyfin (guitar library) |
| 8123 | Home Assistant |
| 8384 | Syncthing UI |
| 9100, 9101 | node exporter, cAdvisor |
| UDP 41641 | Tailscale |
| UDP 1900, 5353, 9999, 20002 | Home Assistant device discovery |

**gmktec** uses scoped `extraInputRules`, except SSH and the exporters:

| Port | Service | Admits |
|------|---------|--------|
| 22 | SSH | any |
| 9100, 9101 | node exporter, cAdvisor | any |
| 8000 | restic REST server | trigkey only |
| 8080, 9696, 8989, 7878 | SABnzbd, Prowlarr, Sonarr, Radarr | LAN |
| 8096, UDP 7359 | Jellyfin, Jellyfin discovery | LAN |
| 5000 | Piper TTS | LAN |
| 8081 | `llama-server`, when started by hand with `--host 0.0.0.0` | LAN |

Portless adds TCP 1355 and UDP 5353, scoped to the LAN, on both hosts.

**Don't use `openFirewall = true` on gmktec.** It opens the port on every interface, and some modules open extra ports (Jellyfin adds DLNA). One scoped `extraInputRules` line opens exactly one thing.

## Portless — LAN names

[Portless](https://portless.sh) gives LAN services a `<alias>.local` name, so nobody needs a port number. Both hosts run it. Module: `hosts/nixos/optional/portless.nix`.

### Add a name

1. In `inventory.nix`, under the host's `portlessAliases`, add `<alias> = { port = <port>; name = "<Display Name>"; };`
2. Rebuild that host.
3. Rebuild trigkey. This adds the probe to the **Portless Services** dashboard.

The key is the mDNS name, so keep it a slug. `name` is only the dashboard label.

### Current names

| Name | Host | Port | Serves |
|------|------|------|--------|
| `sonarr.local` | gmktec | 8989 | Sonarr |
| `radarr.local` | gmktec | 7878 | Radarr |
| `prowlarr.local` | gmktec | 9696 | Prowlarr |
| `sabnzbd.local` | gmktec | 8080 | SABnzbd |
| `jellyfin.local` | gmktec | 8096 | Jellyfin |
| `finance.local` | gmktec | 5174 | local-finance dev server, started by hand |
| `papra.local` | gmktec | 1221 | Papra |
| `trigkey.finance.local` | trigkey | 5174 | local-finance dev server, started by hand |
| `ladder.local` | trigkey | 4210 | Ladder |
| `flaresolverr.local` | trigkey | 8191 | FlareSolverr |

### Rules

- **One host per name.** mDNS renames a duplicate (`jellyfin-2.local`), and which host wins changes across reboots. The host you develop on owns the bare name; the other prefixes its host name (`trigkey.finance`).
- **`.local` is required.** mDNS answers only for `.local` ([RFC 6762](https://www.rfc-editor.org/rfc/rfc6762)), and portless forces it in LAN mode.
- **Multi-label names** like `trigkey.finance.local` work on Linux and Apple devices, not Windows' built-in mDNS. Use `trigkey-finance` if Windows needs it.
- **A host can't reach its own names.** The port-80 redirect is prerouting only. On the host, use `curl -sI -H "Host: <alias>.local" http://127.0.0.1:1355/`
- **Is it up?** Check the Grafana **Portless Services** dashboard. See [Monitoring](services/monitoring.md#portless-probes).

HTTPS is off, because every client would need portless's CA installed. Flip `services.portless.tls` to change that. `/var/lib/portless` is not backed up: routes are declared in config, and the CA regenerates.

## Internal networking

- Both hosts use DHCP on `enp1s0`. Reserve the `inventory.nix` addresses by MAC in the router.
- `incusbr0` is the LXC bridge. `docker-services` has the static address `10.0.100.10`, and nftables forwards between the bridge and the host.
- Inside the LXC, Docker DNS resolves container names. See [Architecture](architecture.md#when-to-use-which).

## When Pangolin is broken

Get in over Tailscale: `ssh eric@trigkey`. See [Tailscale](services/tailscale.md).
