# Hermes Agent

Nous Research's AI agent on trigkey: a systemd gateway plus the `hermes` CLI, sharing one state directory.

```bash
hermes chat                     # talk to it
hermes model                    # show the model
hermes auth add xai-oauth       # sign in to xAI again
systemctl status hermes-agent   # the gateway
```

| Item | Value |
|------|-------|
| Module | `hosts/nixos/optional/hermes-agent.nix` |
| Upstream | https://hermes-agent.nousresearch.com |
| Model | `grok-4.3` via `xai-oauth`, base URL `https://api.x.ai/v1`. Pinned in Nix, which wins on every activation. |
| State | `/var/lib/hermes/.hermes`, `hermes:hermes`, setgid, `UMask` `0007` |
| Access | `eric` is in the `hermes` group, so the CLI shares the gateway's state |
| Backup | `/var/lib/hermes` is in the restic `system-state` job |

Not built yet: messaging gateways (Telegram, Discord) through `environmentFiles`, with their tokens in sops under `hermes/env`.
