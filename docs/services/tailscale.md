# Tailscale

Mesh VPN configured on the Trigkey host.

## Overview
- **Type**: Native NixOS service
- **Module**: `hosts/nixos/optional/tailscale.nix`

## Configuration highlights
- Auth key stored in sops (`tailscale/authkey`)
- `--ssh` flag enabled for passwordless SSH over Tailscale
- `--accept-dns=false` to keep local DNS as primary
- Firewall UDP port 41641 opened automatically

## Usage
```bash
# Check status
tailscale status

# SSH to trigkey via Tailscale
ssh eric@trigkey
```

## Notes
- Useful for remote access without opening public ports.
- Works alongside Newt/Pangolin for different access patterns.
