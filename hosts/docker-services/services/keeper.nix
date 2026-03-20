{ config, ... }:

{
  virtualisation.oci-containers.containers = {

    # ── Standalone (web + API + cron + worker + Redis + PostgreSQL + Caddy) ───
    # Env vars in sops: BETTER_AUTH_SECRET, ENCRYPTION_KEY, TRUSTED_ORIGINS
    # Optional: GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
    #           MICROSOFT_CLIENT_ID, MICROSOFT_CLIENT_SECRET
    keeper = {
      image   = "ghcr.io/ridafkih/keeper-standalone:2.9";
      ports   = [ "3005:80" ];
      volumes = [ "/srv/keeper/data:/var/lib/postgresql/data" ];
      environmentFiles = [ config.sops.secrets."docker-services/keeper/env".path ];
    };

  };
}
