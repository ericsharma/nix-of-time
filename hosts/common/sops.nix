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

      # Garage object store
      # rpc-secret:   raw 64-char hex  (openssl rand -hex 32)
      # admin-token:  raw token string (openssl rand -hex 16)
      "garage/rpc-secret"  = { owner = "garage"; };
      "garage/admin-token" = { owner = "garage"; };

      # Garage Web UI — env file
      # API_ADMIN_KEY=<same value as garage/admin-token>
      # AUTH_USER_PASS=<user>:<bcrypt hash>  (optional basic auth)
      "garage-webui/env" = {};

      # Restic backup — Immich media
      # password:  the restic repo encryption passphrase
      # env:       AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, RESTIC_REPOSITORY
      #            (pointing at your Garage S3 endpoint + bucket)
      "restic/immich/password" = {};
      "restic/immich/env"      = {};

      # ── Migrated services from Proxmox ─────────────────────────────────────

      # Strava Statistics
      # STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, STRAVA_REFRESH_TOKEN
      "strava/env" = {};

      # Koito
      # KOITO_DATABASE_URL, KOITO_ALLOWED_HOSTS, KOITO_DEFAULT_USERNAME,
      # KOITO_DEFAULT_PASSWORD, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
      "koito/env" = {};

      # Karakeep (Hoarder)
      # NEXTAUTH_SECRET, MEILI_MASTER_KEY, OPENAI_API_KEY,
      # NEXTAUTH_URL=http://localhost:3088
      "karakeep/env" = {};

      # Dawarich
      # POSTGRES_USER, POSTGRES_PASSWORD
      "dawarich/env" = {};

    };
  };
}
