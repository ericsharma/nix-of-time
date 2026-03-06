{ config, ... }:

{
  sops = {
    # Default secrets file
    defaultSopsFile = ../../secrets/secrets.yaml;

    # Decrypt secrets using the host's SSH key
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    # Secrets definitions
    secrets = {
      # User password for eric
      # Set neededForUsers = true to make available during user creation
      "user-password/eric" = {
        neededForUsers = true;
      };

      # Example secrets for future use:
      # ----------------------------

      # API keys / tokens
      # "api/github-token" = {
      #   owner = "eric";
      #   group = "users";
      #   mode = "0400";
      # };

      # Service credentials
      # "services/db-password" = {
      #   owner = "postgres";
      #   group = "postgres";
      # };

      # SSH keys
      # "ssh/deploy-key" = {
      #   owner = "eric";
      #   mode = "0600";
      # };
    };
  };
}
