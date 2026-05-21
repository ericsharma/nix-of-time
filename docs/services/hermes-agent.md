# Hermes Agent

Nous Research's Hermes Agent running on the Trigkey host.

## Overview

- **Type**: Native NixOS service + CLI tool
- **Module**: `hosts/nixos/optional/hermes-agent.nix`
- **Upstream**: https://hermes-agent.nousresearch.com

## Key Details

- State directory: `/var/lib/hermes/.hermes` (owned by `hermes:hermes` with setgid bit)
- Systemd service: `hermes-agent`
- User access: `eric` is added to the `hermes` group so the CLI shares state with the running service
- UMask set to `0007` to allow proper group read/write on shared files

## Configuration

Currently pinned to:
- Model: `grok-4.3`
- Provider: `xai-oauth`
- Base URL: `https://api.x.ai/v1`

## Usage

```bash
# Check service status
systemctl status hermes-agent

# Use the CLI (shares state with the service)
hermes chat
hermes model
hermes auth add xai-oauth
```

## Future Work

- Add messaging gateways (Telegram, Discord, etc.) via `environmentFiles`
- Consider storing API keys in sops under `hermes/env`
