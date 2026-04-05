{ config, ... }:

{
  # ── Vaultwarden (self-hosted Bitwarden) ───────────────────────────────────
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN            = "https://vault.ericsharma.xyz";
      SIGNUPS_ALLOWED   = false;
      ROCKET_ADDRESS    = "127.0.0.1";
      ROCKET_PORT       = 8222;
      WEBSOCKET_ENABLED = true;
    };
    environmentFile = config.sops.secrets."vaultwarden/env".path;
  };

  sops.secrets."vaultwarden/env" = {
    owner = "vaultwarden";
  };
}
