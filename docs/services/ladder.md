# Ladder and FlareSolverr

Ladder fetches paywalled pages as Googlebot, and FlareSolverr solves Cloudflare challenges for it. Both are Podman containers on trigkey, reachable on the LAN only.

## Use it

Put the article URL after the Ladder URL:

```
http://ladder.local/https://www.example.com/some/article
```

Or open `http://ladder.local` and paste the URL into the form.

| Service | LAN name | Port | Module | Image |
|---------|----------|------|--------|-------|
| Ladder | `ladder.local` | 4210 | `hosts/nixos/optional/ladder.nix` | `ladder:v0.0.23` |
| FlareSolverr | `flaresolverr.local` | 8191 | `hosts/nixos/optional/flaresolverr.nix` | `flaresolverr:v3.5.2` |

Both bind `127.0.0.1`; portless puts them on the LAN. Both are stateless and not backed up.

## A site stopped working

Try these in order:

1. **Restart Ladder.** It downloads the community ruleset from GitHub at start, unpinned, so fixes and regressions both arrive this way.
   ```bash
   sudo systemctl restart podman-ladder
   ```
2. **Check that Ladder can reach FlareSolverr.** A broken link shows no error; Cloudflare sites just fail. Expect `{"msg": "FlareSolverr is ready!", ...}`.
   ```bash
   sudo podman run --rm --network=ladder docker.io/library/busybox:1.36 \
     sh -c 'wget -qO- --timeout=10 http://flaresolverr:8191/'
   ```
3. **Upgrade FlareSolverr.** Bump its pinned tag. It tracks Cloudflare's changes.
4. **Read the logs:** `journalctl -u podman-ladder -n 50` and `journalctl -u podman-flaresolverr -n 50`. To see one site's traffic, set `LOG_URLS=true` (Ladder) or `LOG_HTML=true` (FlareSolverr) in the module, then set it back.
5. **Still failing?** The site likely withholds the article until you log in. No ruleset fixes that.

## The private network

Ladder calls `http://flaresolverr:8191` by container name, resolved by aardvark-dns on the podman network `ladder` (created by `podman-network-ladder.service`).

- The bridge name and subnet are pinned (`--interface-name podman-ladder`, `--subnet 10.89.1.0/24`), because the firewall rule names the interface.
- The host firewall drops by default, so a rule admits DNS on `podman-ladder`. Without it, every lookup times out.
- The network is created only if it's missing. After changing either flag, recreate it:

```bash
sudo systemctl stop podman-ladder podman-flaresolverr podman-network-ladder
sudo podman network rm ladder
sudo systemctl start podman-network-ladder podman-flaresolverr podman-ladder
```

## Cautions

- **No authentication.** Anyone on the Wi-Fi can use both. Never add a Pangolin route without setting `USERPASS` on Ladder first. An open proxy gets found, and the traffic leaves from this address.
- **FlareSolverr needs `--shm-size=1g`.** Chrome writes to `/dev/shm`, and podman's 64M default crashes mid-solve. It shows up as a timeout, not an out-of-memory error.
- **`curl http://ladder.local` from trigkey returns nothing.** Test from another device, or run `curl -sI -H "Host: ladder.local" http://127.0.0.1:1355/`
