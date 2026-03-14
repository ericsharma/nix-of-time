# Secrets management

All secrets are in `secrets/secrets.yaml`, encrypted with [age](https://github.com/FiloSottile/age) via [sops-nix](https://github.com/Mic92/sops-nix).

## How it works

Each host decrypts using its own SSH ed25519 key at `/etc/ssh/ssh_host_ed25519_key`. The `.sops.yaml` file at the repo root defines which age keys can decrypt which secrets files.

Three age keys are configured as recipients:

| Key | Purpose |
|-----|---------|
| `&personal` | Workstation key for editing secrets |
| `&trigkey` | Trigkey host SSH key (converted to age) |
| `&docker-services` | LXC container SSH key (converted to age) |

## Editing secrets

```bash
sops secrets/secrets.yaml
```

## Adding a new secret

1. Define the secret in the relevant `sops.nix`:
   - Trigkey: `hosts/common/sops.nix`
   - Docker-services: `hosts/docker-services/sops.nix`

2. Add the value in sops:
   ```bash
   sops secrets/secrets.yaml
   ```

3. Reference it in your service config:
   ```nix
   # As an environment file
   environmentFiles = [ config.sops.secrets."myservice/env".path ];

   # As a raw secret path
   config.sops.secrets."myservice/token".path
   ```

## Secret naming conventions

Secrets are namespaced by service:

```
user-password/eric          # User passwords
newt/env                    # Newt tunnel credentials
vaultwarden/env             # Vaultwarden admin token
garage/rpc-secret           # Garage raw secrets
komodo/env                  # Komodo env file
docker-services/koito/env   # Container-scoped secrets
```

## Adding a new sops recipient

When adding a new host that needs to decrypt secrets:

1. Get the host's SSH ed25519 public key
2. Convert to age: `nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'`
3. Add the key to `.sops.yaml` with an anchor name
4. Add the anchor to the relevant `creation_rules` entry
5. Re-encrypt: `sops updatekeys secrets/secrets.yaml`
