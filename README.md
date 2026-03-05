# nixos-config

Flake-based NixOS configuration for Eric Sharma's machines.

## Structure

```
nixos-config/
├── flake.nix
└── hosts/
    ├── common/
    │   └── default.nix        # Shared config: user, SSH, packages, nix-ld, timezone
    └── trigkey/               # Trigkey mini PC
        ├── default.nix        # Host-specific: networking, boot, firewall
        └── hardware-configuration.nix
```

Adding a new machine: create `hosts/<name>/`, import `../common`, add to `flake.nix`.

## Applying changes

From `~/nixos-config/`:

```bash
sudo nixos-rebuild switch --flake .#trigkey
```

To test without making it the boot default (safe for risky changes):

```bash
sudo nixos-rebuild test --flake .#trigkey
```

## SSH

Password authentication is disabled. Key-only login as `eric`:

```bash
ssh eric@<ip>
```

`eric` is in the `wheel` group with passwordless sudo.

## Claude Code

Install using the official native installer (recommended — do **not** use npm):

```bash
curl -fsSL https://claude.ai/install.sh | sh
```

`nix-ld` is enabled system-wide so the installer works out of the box after a
rebuild. The dev shell (`nix develop`) provides Node.js for other tooling but
Claude Code should always be installed via the native installer above.

## GitHub SSH setup

```bash
cat ~/.ssh/id_ed25519.pub   # copy this
# Add at: https://github.com/settings/ssh/new
ssh -T git@github.com       # verify
```

## Workflow

```bash
# Edit configuration
vim ~/nixos-config/hosts/trigkey/default.nix

# Apply
sudo nixos-rebuild switch --flake ~/nixos-config#trigkey

# Commit and push
git add -p
git commit -m "describe change"
git push
```
