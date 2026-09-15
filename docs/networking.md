# Networking and exposure

Nothing in this fleet listens on a public port. Every route to the internet
goes through an outbound tunnel, and every service starts from the assumption
that it binds to loopback.

This page collects the exposure rules that are otherwise spread across two
dozen modules.

## The three tiers of exposure

| Tier | How | When to use it |
|------|-----|----------------|
| **Loopback only** | `127.0.0.1:<port>` and no firewall rule | The default. Use it unless you have a stated reason not to. |
| **LAN** | An explicit firewall rule, scoped to `192.168.0.0/24` where possible | The service is genuinely useful from a phone or laptop on the Wi-Fi, and it is safe without a login. |
| **Public** | A Pangolin route to a loopback port. Never a firewall rule. | The service needs to work away from home. |

Move a service up a tier only with a reason. Never move one up "for
convenience" — a LAN-open port on a service with no login is a decision, not a
default.

## Public exposure — Newt and Pangolin

Newt runs on trigkey (`hosts/nixos/trigkey/newt.nix`) and dials out to
`https://pangolin.ericsharma.xyz`. The tunnel is outbound, so **no inbound port
is open and no port is forwarded on the router**. Its credentials live in sops
at `newt/env`.

To publish a service:

1. Confirm it binds to `127.0.0.1`.
2. Add a route in the Pangolin dashboard: `<name>.ericsharma.xyz` to
   `127.0.0.1:<port>`.

There is nothing to add to the NixOS config. That is the point.

**gmktec has no Newt.** Nothing on that machine can be published this way. That
is why the whole Usenet stack is LAN only, and why MeshLLM is reached over an
SSH tunnel instead.

### Known public routes

| Name | Serves |
|------|--------|
| `pangolin.ericsharma.xyz` | The Pangolin control plane |
| `radio.ericsharma.xyz` | Icecast, port 8000 |
| `video.ericsharma.xyz` | EternaTV, port 8088 |
| `vault.ericsharma.xyz` | Vaultwarden |
| `d.ericsharma.xyz` | Dawarich |
| `tracking.ericsharma.xyz` | Rybbit |
| `options.ericsharma.xyz` | Options Ledger |
| `bellewatsonstudio.com` | Belle Watson Studios |
| `ericsharma.xyz` | The personal site |

The Pangolin dashboard is the authority. This table is a convenience copy and
will drift.

## Firewall

Both hosts run `networking.firewall.enable = true` and open port 22 only in
their base config. Everything else is added by the module that needs it.

**Ports open on trigkey**

| Port | Service |
|------|---------|
| 22 | SSH |
| 3900 | Garage S3 API |
| 5757 | Opened in the base config with no comment. Identify it before you remove it. |
| 8096 | Jellyfin — the guitar library |
| 8384 | Syncthing UI |
| 3030 | Dawarich nginx proxy |
| 9100, 9101 | node exporter, cAdvisor |

**Ports open on gmktec**

gmktec uses scoped nftables rules instead of `allowedTCPPorts`, so every rule
names a source subnet:

| Port | Service | Admits |
|------|---------|--------|
| 22 | SSH | any |
| 7878, 8989, 9696, 8080 | Radarr, Sonarr, Prowlarr, SABnzbd | `192.168.0.0/24` |
| 8096 | Jellyfin — the `/data` library | `192.168.0.0/24` |
| 8000 | restic REST server | trigkey only |
| 8081 | `llama-server`, when started by hand | `192.168.0.0/24` |

### Why not `openFirewall`

Several upstream modules offer `openFirewall = true`. gmktec never uses it, for
two reasons:

- It publishes the port on **every** interface, not just the LAN.
- Some modules open more than you expect. Jellyfin's `openFirewall` also opens
  the DLNA ports, which nothing here uses.

A scoped `extraInputRules` line states the intent exactly.

### Services with no login

SABnzbd has no account at all, and Prowlarr runs with
`AuthenticationRequired=DisabledForLocalAddresses`. Sonarr and Radarr take the
same posture. This is only safe because the nftables rules admit
`192.168.0.0/24` alone and gmktec has no Newt route.

Do not put any of them on the public path without revisiting **both** of those
facts first.

A `curl -I` (HEAD) against Prowlarr answers 401 even from the LAN. That is
normal — use a GET.

## Portless — LAN names

[Portless](https://portless.sh) gives every LAN service a friendly
`<alias>.local` name, so nobody has to remember a port. The module is
`hosts/nixos/optional/portless.nix`.

It runs a proxy on port 80 and publishes each alias as an mDNS record through
avahi on 5353/udp. Any device on the Wi-Fi resolves the name with no change to
`/etc/hosts` and no router DNS entry.

**Both hosts enable it.** Each declares its own aliases in its
`default.nix`; the module activates only when `services.portless.aliases` is
not empty, which is why the file can sit in `optional/` and be globbed by
trigkey harmlessly.

gmktec — `hosts/nixos/gmktec/default.nix`:

| Name | Shown as | Goes to |
|------|----------|---------|
| `http://sonarr.local` | Sonarr | 8989 |
| `http://radarr.local` | Radarr | 7878 |
| `http://prowlarr.local` | Prowlarr | 9696 |
| `http://sabnzbd.local` | SABnzbd | 8080 |
| `http://jellyfin.local` | Jellyfin | 8096 |
| `http://finance.local` | Local Finance | 5174 — local-finance dev server, started by hand |
| `http://papra.local` | Papra | 1221 — document management and archiving |

trigkey — `hosts/nixos/trigkey/default.nix`:

| Name | Shown as | Goes to |
|------|----------|---------|
| `http://trigkey.finance.local` | Local Finance (trigkey) | 5174 — local-finance dev server, started by hand |
| `http://ladder.local` | Ladder | 4210 — paywall-stripping web proxy |

Both maps are declared in `inventory.nix`, not in the host files — monitoring
reads the same data to build a blackbox probe per alias, so one edit adds the
name and its dashboard row together. Add an entry, rebuild that host, rebuild
trigkey for the probe.

Each entry is `{ port; name; }`. The attribute key is the mDNS name and is what
the proxy routes on, so it stays a slug; `name` is free text, is never resolved,
and exists only so the **Portless Services** dashboard reads "SABnzbd" instead
of `sabnzbd`. It defaults to the alias if left out. Qualify it only when two
hosts publish the same service — hence "Local Finance (trigkey)".

### Is it up?

The **Portless Services** dashboard in Grafana shows every name in the table
above, from both hosts, with live status, HTTP code, and response time. The
probe runs through the proxy, so it catches both a dead service and a lost
route. See [Monitoring](services/monitoring.md#portless-services-portless-services).

### Naming across two hosts

mDNS resolves a duplicate name by suffixing it — `jellyfin-2.local` — and which
host wins is unpredictable across reboots, so a name may be published from one
host only. See [Jellyfin](media/jellyfin.md#the-mdns-name-collision).

The convention: **the host you work on owns the bare name, the other prefixes
its own host name.** local-finance runs on :5174 on both boxes, so gmktec (where
development happens) publishes `finance.local` and trigkey publishes
`trigkey.finance.local`. Moving development to the other box is a two-line swap.

An alias name may hold dots. Portless appends `.local` and publishes the whole
string, so `trigkey.finance` becomes the multi-label mDNS name
`trigkey.finance.local`. This resolves on avahi/nss-mdns and on Bonjour.
Windows' built-in mDNS client handles single-label `.local` names only, so use
`trigkey-finance` instead if a Windows client ever needs the name.

### The `.local` suffix is not optional

`finance.trigkey` cannot work. mDNS only ever answers for `.local`
([RFC 6762](https://www.rfc-editor.org/rfc/rfc6762)), and portless enforces the
same: it has a `--tld` flag, but `resolveProxyConfig` hard-sets `tld = "local"`
whenever LAN mode is on, and LAN mode is what emits the mDNS records. A custom
TLD would mean running a real DNS server for the LAN and pointing the router at
it — a different system, not a portless option.

### Two deliberate choices

**HTTPS is off.** Portless can mint its own CA and serve `*.local` over TLS,
but then every client device needs that CA installed once. For LAN-only UIs
that already have no login, the trust dance costs more than the padlock is
worth. Flip `services.portless.tls` if that changes.

**State is not backed up.** `/var/lib/portless` holds the CA cert and the route
registrations. Every route is declared in the config, and the CA regenerates
when you wipe the state directory.


## Internal networking

- Both hosts take DHCP on `enp1s0`. `inventory.nix` records fixed addresses, so
  reserve them against each MAC in the router.
- The Incus bridge `incusbr0` carries the LXC network. `docker-services` has
  the static address `10.0.100.10`.
- nftables rules forward between the bridge and the host.
- Inside the LXC, Docker's built-in DNS resolves container names. That is the
  whole reason multi-container stacks live there instead of on Podman. See
  [Architecture](architecture.md#when-to-use-which).

## Tailscale

Tailscale provides a mesh VPN with SSH support, in parallel to all of the
above. It is the way in when Pangolin is the thing that is broken. See
[Tailscale](services/tailscale.md).
