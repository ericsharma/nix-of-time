# Secrets

All secrets live in one file, `secrets/secrets.yaml`, encrypted with age through sops-nix.

## Edit

```bash
nix develop -c sops secrets/secrets.yaml
```

## Add a secret

1. Add the value with the command above, nested under the service name.
2. Declare it:
   - trigkey or gmktec: in the service's own module, `sops.secrets."<svc>/env" = { };`
   - docker-services: in `hosts/nixos/docker-services/sops.nix`, `"docker-services/<svc>/env" = { };`
3. Use it: `config.sops.secrets."<svc>/env".path`
4. Deploy the host.

Two shapes:

```yaml
myservice:
  env: |          # env block, for environmentFile / EnvironmentFile=
    API_KEY=...
    DB_PASSWORD=...
  token: abc123   # scalar, for an option that takes a path to one secret
```

Names follow `<service>/<key>`: `newt/env`, `grafana/env`, `garage/rpc-secret`, `user-password/eric`, `docker-services/koito/env`.

## Who can decrypt

Each host decrypts with its own SSH host key (`/etc/ssh/ssh_host_ed25519_key`) converted to age. `.sops.yaml` sets the recipients.

| File | Recipients |
|------|------------|
| `secrets/secrets.yaml` | personal, trigkey, docker-services, gmktec, m1-mini |
| `secrets/m1-mini/*.yaml` | the same five |
| `secrets/claude-skills.tar.gz` | personal, trigkey |

Every recipient can read every secret in its file. A new host sees all of `secrets.yaml`, not only its own entries.

## Adding a new sops recipient

1. Get the host's age key: `nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`. On a fresh install, make the key under `/mnt` before `nixos-install`. See [Adding a machine](adding-a-machine.md#2-partition-format-make-the-host-key).
2. In `.sops.yaml`, add the key as an anchor and add the anchor to the right `creation_rules` entry.
3. Re-encrypt: `nix develop -c sops updatekeys secrets/secrets.yaml`
4. Deploy. On a fresh install, the log must show `sops-install-secrets: Imported /etc/ssh/ssh_host_ed25519_key as age key`.

## gmktec's GitHub deploy key

gmktec pushes with a read-write repo deploy key, not eric's personal key, so you can commit on either machine.

| Item | Value |
|------|-------|
| Private key | `~/.ssh/id_ed25519` on gmktec, comment `gmktec-deploy` |
| GitHub | `ericsharma/nix-of-time`, deploy key titled `gmktec`, read-write |
| Also used by | trigkey's `authorizedKeys`, so gmktec can SSH into trigkey |

**It is not declarative.** Reinstalling gmktec loses it. It stays out of sops on purpose, because every recipient would get the private key.

To replace it:

```bash
ssh eric@192.168.0.51 'ssh-keygen -t ed25519 -N "" -C gmktec-deploy -f ~/.ssh/id_ed25519'
gh repo deploy-key delete <id> --repo ericsharma/nix-of-time
gh repo deploy-key add <pubkey-file> --repo ericsharma/nix-of-time --title gmktec --allow-write
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts
```

- Before trusting the last line, confirm GitHub's ed25519 fingerprint is `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU` ([published keys](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints)).
- Then put the new public key in `hosts/nixos/trigkey/default.nix` and `rebuild` trigkey.

`rebuild-docker` does not work from gmktec. `10.0.100.10` is on `incusbr0`, a bridge that exists only on trigkey.
