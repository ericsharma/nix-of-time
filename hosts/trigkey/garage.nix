{ config, pkgs, ... }:

{
  # ── System user ───────────────────────────────────────────────────────────────
  # Stable UID/GID so sops can hand the RPC secret file to the garage process.
  # (The NixOS module defaults to DynamicUser; we override that below.)
  users.users.garage = {
    isSystemUser = true;
    group        = "garage";
  };
  users.groups.garage = {};

  # ── Secrets ───────────────────────────────────────────────────────────────────
  # garage/rpc-secret must contain the raw 64-char hex string only — no KEY=VALUE.
  # Generate with: openssl rand -hex 32
  sops.secrets."garage/rpc-secret" = {
    owner = "garage";
  };

  # garage/admin-token: raw token string — used by the daemon and passed to
  # garage-webui as API_ADMIN_KEY. Generate with: openssl rand -hex 16
  sops.secrets."garage/admin-token" = {
    owner = "garage";
  };

  # ── Garage daemon ─────────────────────────────────────────────────────────────
  services.garage = {
    enable  = true;
    package = pkgs.garage_2;  # pin explicitly; read release notes before upgrading major versions

    settings = {
      replication_factor = 1;   # single node; bump to 3 when cluster is ready
      db_engine = "lmdb";

      metadata_dir = "/var/lib/garage/meta";
      data_dir     = "/var/lib/garage/data";

      # Secret read directly from file — never touches the nix store
      rpc_secret_file = config.sops.secrets."garage/rpc-secret".path;

      # RPC — used for inter-node communication; kept open for future cluster
      rpc_bind_addr   = "[::]:3901";
      rpc_public_addr = "192.168.0.202:3901";

      s3_api = {
        s3_region     = "garage";
        api_bind_addr = "[::]:3900";
        root_domain   = ".s3.local";
      };

      # Admin API — localhost only
      admin = {
        api_bind_addr    = "127.0.0.1:3903";
        admin_token_file = config.sops.secrets."garage/admin-token".path;
      };
    };
  };

  # Disable DynamicUser so the stable `garage` user above owns the process and
  # can read the sops-managed secret file.
  systemd.services.garage.serviceConfig = {
    DynamicUser = false;
    User        = "garage";
    Group       = "garage";
  };

  # ── Firewall ──────────────────────────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [ 3900 ];

  # ── Post-deploy one-time setup (run manually after first `nixos-rebuild switch`) ──
  #
  # 1. Apply node layout (25 GB allocated on root NVMe, zone dc1):
  #      sudo garage layout assign -z dc1 -c 25G $(sudo garage node id | cut -d@ -f1)
  #      sudo garage layout apply --version 1
  #
  # 2. Create buckets:
  #      sudo garage bucket create <name>
  #
  # 3. Create an access key and grant it to a bucket:
  #      sudo garage key create <key-name>
  #      sudo garage bucket allow <name> --read --write --owner --key <key-name>
  #
  # 4. Store the resulting key ID + secret in sops for services that need S3 access.
  #
  # When the second node joins the cluster, re-run layout assign for that node,
  # then apply with an incremented --version number.
}
