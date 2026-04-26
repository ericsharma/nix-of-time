{ ... }:

{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Decrypt using this container's SSH host key
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      "docker-services/koito/env"     = {};
      "docker-services/karakeep/env"  = {};
      "docker-services/dawarich/env"  = {};
      "docker-services/periphery/env" = {};
      "docker-services/keeper/env"   = {};
      "docker-services/rybbit/env"    = {};

      # Cobalt: full keys.json scalar, mounted into the container as a file.
      # World-readable so the container's non-root user can read it.
      "docker-services/cobalt/keys.json" = { mode = "0444"; };
    };
  };
}
