# nixos-config

Flake-based NixOS configuration for Eric Sharma's machine.

## Structure

```
nixos-config/
├── flake.nix                  # Flake inputs, system config, dev shell
└── nixos/
    ├── configuration.nix      # System options (networking, packages, services)
    └── hardware-configuration.nix  # Auto-generated hardware scan output
```

## Applying changes

From `~/nixos-config/`:

```bash
sudo nixos-rebuild switch --flake .#nixos
```

To test without making it the boot default:

```bash
sudo nixos-rebuild test --flake .#nixos
```

## Claude Code dev shell

The flake includes a dev shell with Node.js for running Claude Code:

```bash
nix develop                                        # enter the shell
npm install -g @anthropic-ai/claude-code           # install claude CLI
claude                                             # run it
```

`nix-ld` is enabled system-wide, so the native Linux installer from
https://claude.ai/download also works after a rebuild.

## Networking

Configured for DHCP Ethernet on `enp1s0`. No Wi-Fi, no NetworkManager.
Change the interface name in `nixos/configuration.nix` if hardware changes.

## GitHub SSH setup

Public key (already generated at `~/.ssh/id_ed25519.pub`):

1. Copy the key: `cat ~/.ssh/id_ed25519.pub`
2. Add it at: https://github.com/settings/ssh/new
3. Test: `ssh -T git@github.com`
4. Add remote: `git remote add origin git@github.com:YOUR_USERNAME/nixos-config.git`
5. Push: `git push -u origin main`

## Workflow

```bash
# Edit configuration
vim ~/nixos-config/nixos/configuration.nix

# Apply
sudo nixos-rebuild switch --flake ~/nixos-config#nixos

# Commit and push
cd ~/nixos-config
git add -p
git commit -m "describe change"
git push
```
