{ config, ... }:

{
  # ── Karakeep / Hoarder (bookmark manager) ────────────────────────────────────
  # Data dirs: /srv/karakeep/{data,meilisearch}
  # Port: 3088

  sops.secrets."karakeep/env" = {};

  virtualisation.oci-containers.containers.karakeep-chrome = {
    image = "gcr.io/zenika-hub/alpine-chrome:123";
    cmd = [
      "--no-sandbox"
      "--disable-gpu"
      "--disable-dev-shm-usage"
      "--remote-debugging-address=0.0.0.0"
      "--remote-debugging-port=9222"
      "--hide-scrollbars"
    ];
    extraOptions = [ "--network=karakeep" ];
  };

  virtualisation.oci-containers.containers.karakeep-meilisearch = {
    image = "getmeili/meilisearch:v1.13.3";
    volumes = [
      "/srv/karakeep/meilisearch:/meili_data"
    ];
    environment = {
      MEILI_NO_ANALYTICS = "true";
    };
    environmentFiles = [
      config.sops.secrets."karakeep/env".path
    ];
    extraOptions = [ "--network=karakeep" ];
  };

  virtualisation.oci-containers.containers.karakeep = {
    image = "ghcr.io/karakeep-app/karakeep:release";
    dependsOn = [ "karakeep-chrome" "karakeep-meilisearch" ];
    ports = [ "127.0.0.1:3088:3000" ];
    volumes = [
      "/srv/karakeep/data:/data"
    ];
    environmentFiles = [
      config.sops.secrets."karakeep/env".path
    ];
    environment = {
      MEILI_ADDR      = "http://karakeep-meilisearch:7700";
      BROWSER_WEB_URL = "http://karakeep-chrome:9222";
      DATA_DIR        = "/data";
    };
    extraOptions = [ "--network=karakeep" ];
  };

  systemd.services.create-karakeep-network = {
    description = "Create Podman network for Karakeep";
    after = [ "podman.service" ];
    wantedBy = [
      "podman-karakeep.service"
      "podman-karakeep-chrome.service"
      "podman-karakeep-meilisearch.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/run/current-system/sw/bin/podman network create karakeep --ignore";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/karakeep 0755 root root -"
    "d /srv/karakeep/data 0755 root root -"
    "d /srv/karakeep/meilisearch 0755 root root -"
  ];
}
