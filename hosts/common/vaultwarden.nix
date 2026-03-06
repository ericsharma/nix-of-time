{ config, ... }:

{
  # ── Vaultwarden (self-hosted Bitwarden) ───────────────────────────────────
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN            = "https://vault.trigkey.local";
      SIGNUPS_ALLOWED   = false;
      ROCKET_ADDRESS    = "127.0.0.1";
      ROCKET_PORT       = 8222;
      WEBSOCKET_ENABLED = true;
    };
    environmentFile = config.sops.secrets."vaultwarden/env".path;
  };

  # ── Caddy reverse proxy with self-signed TLS ──────────────────────────────
  services.caddy = {
    enable = true;
    virtualHosts."vault.trigkey.local" = {
      extraConfig = ''
        tls internal
        reverse_proxy 127.0.0.1:8222
      '';
    };
  };

  # ── Firewall ──────────────────────────────────────────────────────────────
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # ── Sops secret: admin token + any extra env vars ────────────────────────
  sops.secrets."vaultwarden/env" = {
    owner = "vaultwarden";
  };
}
