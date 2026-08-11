{ ... }:

{
  # Darwin counterpart to hosts/nixos/common/sops.nix. Deliberately separate
  # rather than shared: the NixOS file is pulled in via commonModules, which
  # carries sops-nix.nixosModules.sops and therefore cannot be reused under
  # nix-darwin's module system (see the darwinConfigurations comment in
  # flake.nix). The *shape* is kept identical so the two read the same.
  sops = {
    # m1-mini reads its own per-host file, not the shared secrets/secrets.yaml.
    # That shared file has no m1-mini age recipient, and adding one means
    # re-encrypting it — which needs an existing recipient's *private* key.
    # secrets/m1-mini/*.yaml is the expansion pattern .sops.yaml already
    # documents for precisely this situation, and it encrypts with public keys
    # alone.
    defaultSopsFile = ../../../secrets/m1-mini/llama-server.yaml;

    # Decrypt using the age key derived from this machine's SSH host key, the
    # same mechanism every NixOS host here uses. sops-nix's nix-darwin module
    # already defaults to exactly this path, but it is spelled out to match
    # hosts/nixos/common/sops.nix and to make the dependency obvious: delete
    # /etc/ssh/ssh_host_ed25519_key and every secret on this host stops
    # decrypting.
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Secrets definitions: each service declares its own in its module file.
  };
}
