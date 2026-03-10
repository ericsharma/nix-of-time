{ config, ... }:

{
  virtualisation.oci-containers.containers = {

    karakeep-meilisearch = {
      image   = "getmeili/meilisearch:v1.13.3";
      volumes = [ "/srv/karakeep/meilisearch:/meili_data" ];
      environmentFiles = [ config.sops.secrets."docker-services/karakeep/env".path ];
      environment = { MEILI_NO_ANALYTICS = "true"; };
      extraOptions = [ "--network=karakeep" ];
    };

    karakeep-chrome = {
      image = "gcr.io/zenika-hub/alpine-chrome:123";
      cmd   = [
        "--no-sandbox"
        "--disable-gpu"
        "--disable-dev-shm-usage"
        "--remote-debugging-address=0.0.0.0"
        "--remote-debugging-port=9222"
        "--hide-scrollbars"
      ];
      extraOptions = [ "--network=karakeep" ];
    };

    karakeep-web = {
      image   = "ghcr.io/karakeep-app/karakeep:release";
      ports   = [ "3088:3000" ];
      volumes = [ "/srv/karakeep/data:/data" ];
      environmentFiles = [ config.sops.secrets."docker-services/karakeep/env".path ];
      environment = {
        MEILI_ADDR      = "http://karakeep-meilisearch:7700";
        BROWSER_WEB_URL = "http://karakeep-chrome:9222";
        DATA_DIR        = "/data";
      };
      dependsOn    = [ "karakeep-meilisearch" "karakeep-chrome" ];
      extraOptions = [ "--network=karakeep" ];
    };

  };

  # ── Docker network ────────────────────────────────────────────────────────
  systemd.services.docker-karakeep-meilisearch.preStart = ''
    docker network create karakeep 2>/dev/null || true
  '';
}
