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

      # Newt (Pangolin tunnel client) credentials
      "newt/env" = {};

      # Vaultwarden environment file (ADMIN_TOKEN)
      "vaultwarden/env" = {
        owner = "vaultwarden";
      };

      # Restic backup — Immich media
      # password:  the restic repo encryption passphrase
      # env:       AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, RESTIC_REPOSITORY
      #            (pointing at your Garage S3 endpoint + bucket)
      "restic/immich/password" = {};
      "restic/immich/env"      = {};
    };
  };
}
