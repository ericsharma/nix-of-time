# Ladder and FlareSolverr

Two containers on trigkey that work as a pair. Ladder fetches a page while
pretending to be Googlebot; FlareSolverr is the fallback for sites that will not
serve anyone until a Cloudflare challenge is solved.

| Service | LAN name | Port | Module |
|---------|----------|------|--------|
| Ladder | `http://ladder.local` | 4210 | `hosts/nixos/optional/ladder.nix` |
| FlareSolverr | `http://flaresolverr.local` | 8191 | `hosts/nixos/optional/flaresolverr.nix` |

Both are stateless and neither is backed up. Both bind `127.0.0.1`; the LAN names
come from the portless aliases in `inventory.nix`.

## Using Ladder

Put the article URL after the Ladder URL:

```
http://ladder.local/https://www.example.com/some/article
```

Or open `http://ladder.local` and paste the URL into the form.

Ladder fetches the page server-side with a Googlebot user agent and a Google
crawler address in `X-Forwarded-For`, then applies a community ruleset that
strips the overlay and the scroll lock from known sites. The ruleset is fetched
from GitHub **at container start**, not pinned:

```
RULESET=https://raw.githubusercontent.com/everywall/ladder-rules/main/ruleset.yaml
```

So a site that upstream has just added starts working after
`systemctl restart podman-ladder`, and a site that worked last week can regress
the same way. That is the first thing to check when one site breaks and the rest
are fine.

## Where FlareSolverr comes in

Ladder alone sends one HTTP request. That is enough for a paywall implemented in
page JavaScript, and useless against Cloudflare's interstitial, which wants a
browser that executes the challenge and keeps the resulting cookie.

FlareSolverr runs a real headless Chrome and does exactly that. Ladder is pointed
at it:

```nix
FLARESOLVERR_HOST = "http://flaresolverr:8191";
```

Ladder decides on its own when to use it — there is no per-request switch. A
Cloudflare-fronted site that returned a challenge page before should now return
the article, at the cost of several seconds while Chrome works.

### The two are on a private container network

`flaresolverr` in that URL is a container name, resolved by aardvark-dns on a
user-defined podman network named `ladder`, created by
`podman-network-ladder.service`. Both containers join it with
`--network=ladder`.

This matters because it is the part most likely to break silently. If DNS on
that network stops working, Ladder cannot reach FlareSolverr, and the symptom is
not an error — it is Cloudflare sites quietly failing while everything else
looks healthy. Two things keep it working, and both are easy to undo by
accident:

- The bridge interface name and subnet are **pinned**
  (`--interface-name podman-ladder`, `--subnet 10.89.1.0/24`). Podman otherwise
  names bridges by creation order, and the firewall rule below is written
  against the name.
- A firewall rule admits DNS on that interface. The host firewall is
  `policy drop` and trusts only `lo` and `incusbr0`, so without it every
  in-container lookup times out.

The network is only created if it does not already exist. Changing either of
those flags therefore does **not** take effect on a rebuild — the existing
network has to be removed first:

```bash
sudo systemctl stop podman-ladder podman-flaresolverr podman-network-ladder
sudo podman network rm ladder
sudo systemctl start podman-network-ladder podman-flaresolverr podman-ladder
```

## Checking it works

FlareSolverr is alive (it has no UI; this JSON line is the whole homepage):

```bash
curl -s http://127.0.0.1:8191/
# {"msg": "FlareSolverr is ready!", "version": "3.5.2", ...}
```

Ladder can actually reach FlareSolverr — the check that matters, since a broken
link here is invisible from the outside. Ladder's own image has no shell tools,
so use a throwaway container on the same network:

```bash
sudo podman run --rm --network=ladder docker.io/library/busybox:1.36 \
  sh -c 'wget -qO- --timeout=10 http://flaresolverr:8191/'
```

Both names resolve on the LAN:

```bash
avahi-resolve -n ladder.local flaresolverr.local
```

Note that `curl http://ladder.local` **from trigkey itself** returns nothing.
That is the documented portless behaviour — the port-80 redirect is installed in
prerouting only, so the box cannot reach itself by name. Test from another
device, or use the port:

```bash
curl -sI -H "Host: ladder.local" http://127.0.0.1:1355/
```

Both names are probed every 30s and appear on the **Portless Services**
dashboard in Grafana.

## Limits and cautions

- **Neither has any authentication.** Both are reachable by anything on the
  Wi-Fi, same as the other LAN UIs. Do not put either behind Pangolin without
  setting `USERPASS` on Ladder first — an open paywall proxy on the public
  internet will be found and used by strangers, and that traffic leaves from
  this address.
- **Ladder is not a universal key.** It defeats paywalls that serve the full
  article to crawlers. A site that genuinely withholds the content server-side
  until you log in returns nothing useful, and no ruleset changes that.
- **FlareSolverr is heavy.** Each solve starts a Chrome session. `--shm-size=1g`
  is set because Chrome writes renderer scratch to `/dev/shm`, and podman's 64M
  default crashes a tab mid-solve — which surfaces as an opaque timeout, not an
  out-of-memory error.
- **Both images are pinned** (`ladder:v0.0.23`, `flaresolverr:v3.5.2`). Neither
  auto-updates. FlareSolverr in particular tracks Cloudflare's changes, so an
  upgrade is the second thing to try when challenge sites stop working and a
  restart did not help.

## Logs

```bash
journalctl -u podman-ladder -n 50
journalctl -u podman-flaresolverr -n 50
```

`LOG_URLS=false` on Ladder and `LOG_HTML=false` on FlareSolverr are deliberate:
the defaults write every fetched URL, and the full solved page, into the
journal. Turn them on in the module while debugging a specific site, and turn
them back off.
