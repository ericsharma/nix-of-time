# Tailscale

Mesh VPN on trigkey. It's the way in when Pangolin is broken.

```bash
ssh eric@trigkey    # OpenSSH over the tailnet, with your key
tailscale status
```

| Item | Value |
|------|-------|
| Module | `hosts/nixos/optional/tailscale.nix` |
| Auth key | sops `tailscale/authkey` |
| Flags | `--accept-dns=false` (keep local DNS). No `--ssh`: it skips authorized_keys, and eric has passwordless sudo |
| Firewall | UDP 41641, opened by the module |

gmktec doesn't run Tailscale. The auth key was single-use and trigkey consumed it. To add gmktec, mint a second key, store it under its own sops name, and import a gmktec-local module.
