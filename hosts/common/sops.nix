{ config, ... }:

{
  sops = {
    # Default secrets file
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Decrypt secrets using the host's SSH key
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Secrets definitions
    # Each service declares its own secrets in its module file.
    # Only host-level secrets that don't belong to a specific service live here.
    secrets = {
      # User password for eric
      # neededForUsers = true makes it available during early user creation
      "user-password/eric" = {
        neededForUsers = true;
      };
    };
  };
}
