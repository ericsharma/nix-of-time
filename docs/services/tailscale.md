# Tailscale

Mesh VPN on trigkey. It's the way in when Pangolin is broken.

```bash
ssh eric@trigkey    # Tailscale SSH, no key prompt
tailscale status
```

| Item | Value |
|------|-------|
| Module | `hosts/nixos/optional/tailscale.nix` |
| Auth key | sops `tailscale/authkey` |
| Flags | `--ssh` (SSH by Tailscale identity), `--accept-dns=false` (keep local DNS) |
| Firewall | UDP 41641, opened by the module |

gmktec doesn't run Tailscale. The auth key was single-use and trigkey consumed it. To add gmktec, mint a second key, store it under its own sops name, and import a gmktec-local module.
