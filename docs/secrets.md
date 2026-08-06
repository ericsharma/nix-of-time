# Secrets management

All secrets are in `secrets/secrets.yaml`, encrypted with [age](https://github.com/FiloSottile/age) via [sops-nix](https://github.com/Mic92/sops-nix).

## How it works

Each host decrypts using its own SSH ed25519 key at `/etc/ssh/ssh_host_ed25519_key`. The `.sops.yaml` file at the repo root defines which age keys can decrypt which secrets files.

Four age keys are configured as recipients:

| Key | Purpose |
|-----|---------|
| `&personal` | Workstation key for editing secrets |
| `&trigkey` | Trigkey host SSH key (converted to age) |
| `&docker-services` | LXC container SSH key (converted to age) |
| `&gmktec` | GMKtec host SSH key (converted to age) |

Every recipient decrypts the whole file. A new host therefore reads every
secret, not only its own. Keep this in mind when you add a host.

## Editing secrets

```bash
sops secrets/secrets.yaml
```

## Git deploy key on gmktec

trigkey pushes to GitHub with eric's personal key. gmktec has no such key, so
it uses a repo **deploy key** instead. This lets you edit the config on either
machine, commit, push, and pull on the other.

| Item | Value |
|------|-------|
| Private key | `/home/eric/.ssh/id_ed25519` on gmktec |
| Comment | `gmktec-deploy` |
| GitHub | Repo `ericsharma/nix-of-time`, deploy key titled `gmktec`, **read-write** |

The key is **not declarative**. Nothing in this repo manages it. Reinstall
gmktec and the key is gone. Storing it in `secrets.yaml` would expose a private
key to every host that decrypts that file, so it stays out of sops.

To replace it:

```bash
ssh eric@192.168.0.51 'ssh-keygen -t ed25519 -N "" -C gmktec-deploy -f ~/.ssh/id_ed25519'
gh repo deploy-key delete <id> --repo ericsharma/nix-of-time
gh repo deploy-key add <pubkey-file> --repo ericsharma/nix-of-time --title gmktec --allow-write
```

The host also needs GitHub's host key. Verify the fingerprint against
[GitHub's published keys](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)
before you accept it — the ed25519 one is `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`.

```bash
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts
```

> **Note:** `rebuild-docker` cannot work from gmktec. The LXC address
> `10.0.100.10` sits on `incusbr0`, a bridge local to trigkey. Deploy
> `docker-services` from trigkey only.

## Adding a new secret

1. Define the secret in the relevant `sops.nix`:
   - Trigkey: `hosts/nixos/common/sops.nix`
   - Docker-services: `hosts/nixos/docker-services/sops.nix`

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
grafana/env                 # Grafana admin password
docker-services/koito/env   # Container-scoped secrets
```

## Adding a new sops recipient

When adding a new host that needs to decrypt secrets:

1. Get the host's SSH ed25519 public key
2. Convert to age: `nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`
3. Add the key to `.sops.yaml` with an anchor name
4. Add the anchor to the relevant `creation_rules` entry
5. Re-encrypt: `nix develop -c sops updatekeys secrets/secrets.yaml`

### Order matters on a new install

`hosts/nixos/common/default.nix` reads the `eric` password from sops with
`neededForUsers = true`. A host that cannot decrypt the file gets no user
password. The install still succeeds, so the failure is silent until you try
to log in.

A new host has no SSH host key until `nixos-install` runs, and you need that
key to complete step 2. Break the loop: make the key by hand under `/mnt`
before you install. `nixos-install` keeps it.

```bash
sudo mkdir -p /mnt/etc/ssh
sudo ssh-keygen -t ed25519 -N "" -f /mnt/etc/ssh/ssh_host_ed25519_key
nix-shell -p ssh-to-age --run 'ssh-to-age < /mnt/etc/ssh/ssh_host_ed25519_key.pub'
```

The install log then shows the proof:

```
sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key with fingerprint age1...
```

See [adding-a-machine.md](adding-a-machine.md) for the full procedure.
