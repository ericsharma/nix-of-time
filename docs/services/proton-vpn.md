# Proton VPN

SABnzbd on gmktec downloads through Proton VPN. Nothing else uses the tunnel. Your ISP sees only WireGuard traffic to Proton, and Frugal sees a Proton IP, not the home IP.

```bash
ssh eric@192.168.0.51 'sudo ip netns exec proton curl -s https://ipinfo.io/json | jq -c "{ip,city,org}"'
```

The `org` field must show `Proton AG`.

| Item | Value |
|------|-------|
| Host | gmktec |
| Modules | `hosts/nixos/gmktec/proton-vpn.nix` (namespace), `hosts/nixos/gmktec/sabnzbd.nix` (SABnzbd joins it) |
| Flake input | `vpn-confinement` ([VPN-Confinement](https://github.com/Maroka-chan/VPN-Confinement)) |
| Units | `proton.service` (tunnel), `sabnzbd.service`, `sabnzbd-proxy.socket` |
| WireGuard config | sops `proton/wg-gmktec` (a wg-quick file from Proton) |
| Server | US-NJ#141, P2P |
| Addresses | `192.168.15.1` namespace (SABnzbd), `192.168.15.5` host (bridge `proton-br`) |

## How it works

- SABnzbd runs in the network namespace `proton`. Its only route out is the WireGuard interface `proton0`.
- **Kill switch:** the namespace firewall drops every new connection to the host or the LAN. If the tunnel goes down, SABnzbd stops. It starts again when `proton.service` starts. It never uses the home IP.
- **DNS:** the namespace uses only the `DNS =` line of the config (Proton's `10.2.0.1`). NetShield level 2 filters it.
- **Clients do not change.** `sabnzbd-proxy` listens on `:8080` on the host and forwards to `192.168.15.1:8080`. Sonarr, Radarr, Prowlarr, Chaptarr, `sabnzbd.local`, and the LAN rule use `:8080` as before.
- **SABnzbd cannot reach the host or the LAN.** Give it an `.nzb` file, never a URL on `127.0.0.1`. Sonarr and Radarr send files. The `/add-book` skill downloads the `.nzb` first for this reason.

## Change the server

1. On any device, open account.protonvpn.com → **Downloads** → **WireGuard configuration**. Select **GNU/Linux** and a **P2P** server, then download the file. Keep the `DNS =` line, or the namespace does not start.
2. Copy the file to trigkey, then store it:
   ```bash
   nix develop -c sops set secrets/secrets.yaml '["proton"]["wg-gmktec"]' "$(jq -Rs . < <file>.conf)"
   shred -u <file>.conf
   ```
3. Commit, then deploy gmktec. `restartUnits` restarts the tunnel and SABnzbd.
4. Revoke the old key in the Proton account, under **Downloads** → **WireGuard configuration**.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `sabnzbd.local` does not open, `sabnzbd` is inactive | The tunnel did not start. The start script stops if it cannot ping the Proton endpoint. | `journalctl -u proton -n 30`, then `sudo systemctl restart proton` |
| SABnzbd is up, downloads stay at 0 B/s | The tunnel is up but has no traffic, for example during Proton maintenance | `sudo ip netns exec proton wg show`. If the latest handshake is older than 3 minutes, restart `proton`. If that does not help, change the server. |
| Frugal answers "Access denied to your node" | A stale credential, not the VPN. See the comment on `restartUnits` in `sabnzbd.nix`. | `sudo systemctl restart sabnzbd` |
| A grab fails with a connection error to `127.0.0.1` | A client sent SABnzbd a URL that only the host can reach | Send the `.nzb` file (`mode=addfile`) |

Test a Frugal login from inside the tunnel: SABnzbd → **Config** → **Servers** → **Test Server**.

## Turn it off

1. In `hosts/nixos/gmktec/sabnzbd.nix`, remove the `vpnConfinement` block, `sabnzbd-proxy`, the `ExecStartPost` on `proton`, and `wantedBy = [ "proton.service" ]`.
2. In `hosts/nixos/gmktec/default.nix`, remove the `./proton-vpn.nix` import.
3. Deploy gmktec. SABnzbd listens on `:8080` again directly.

## Add a service to the tunnel

Set `systemd.services.<name>.vpnConfinement = { enable = true; vpnNamespace = "proton"; };`. The service then reaches nothing on the host or the LAN. Clients reach it only through a proxy and a namespace firewall rule, as `sabnzbd.nix` does. A torrent client also needs port forwarding: generate its config with **NAT-PMP** on.
