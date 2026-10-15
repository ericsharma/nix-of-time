# AdGuard Home

AdGuard Home is the DNS server for the LAN and the tailnet. It blocks ads, trackers, malware domains, and iCloud Private Relay. Two instances run natively from the same module, with the same settings.

| Instance | DNS | Web UI | Role |
|----------|-----|--------|------|
| trigkey | `192.168.0.202:53`, `100.73.1.39:53` (tailnet) | `http://adguard.local` | Primary DNS for the LAN; only DNS for the tailnet |
| gmktec | `192.168.0.51:53` | `http://gmktec.adguard.local` | Secondary DNS for the LAN |

- Module: `hosts/nixos/optional/adguardhome.nix`. trigkey imports it through the `optional/` glob. gmktec imports it explicitly.
- Web UI: `127.0.0.1:3010` on each host, put on the LAN by portless. No login.
- Data: `/var/lib/AdGuardHome` on each host. It holds only the query log and stats. Not backed up.
- Each instance has its own query log. To see all queries from a device, look in both web UIs.

## Settings outside this repo

AdGuard serves only the clients that these settings send to it. If you replace one of these devices, set them again.

| Where | Setting | Why |
|-------|---------|-----|
| TP-Link router → Advanced → Network → DHCP Server | Address reservations: trigkey `B0-41-6F-0F-E2-74` → `192.168.0.202`, gmktec → `192.168.0.51` | The DNS addresses must not change |
| Same page | Primary DNS `192.168.0.202`, Secondary DNS `192.168.0.51` | If you leave Secondary empty, the router adds itself and clients skip the blocker. Never use a public DNS server here |
| Router → Advanced → IPv6 | IPv6 **off** | No LAN assigned type lets you set the IPv6 DNS server. The router gives out Spectrum's IPv6 DNS, and clients skip the blocker |
| Tailscale admin → DNS | Nameserver `100.73.1.39`, **Override DNS servers** on | Tailnet devices use AdGuard away from home. gmktec is not on the tailnet, so the tailnet has no fallback |

## Change blocklists or rules

Edit `filters` or `user_rules` in the module. Then deploy **both** hosts (`rebuild` on trigkey, and the gmktec deploy command in `CLAUDE.md`). Rules that you add in the web UI are lost on the next restart, because Nix owns `user_rules`.

To pause blocking for a short time, use **Disable protection** on the dashboard. Do it on both instances, because clients use either one.

## DNS is down

If both instances stop, the whole LAN loses DNS. If trigkey stops, every tailnet device loses DNS.

1. Check the service on the host that failed. It restarts itself every 10 s if it fails.
   ```bash
   systemctl status adguardhome
   journalctl -u adguardhome -n 50
   ```
2. **Bind error on `100.73.1.39` (trigkey):** tailscaled is not up yet. Check it with `tailscale status`.
3. **Fast fallback:** on the router, set Primary DNS to `192.168.0.1`. For tailnet devices, turn off **Override DNS servers** in the Tailscale admin.
