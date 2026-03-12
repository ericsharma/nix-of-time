{ config, lib, pkgs, ... }:

let
  fetchDashboard = { id, hash }: pkgs.fetchurl {
    url  = "https://grafana.com/api/dashboards/${toString id}/revisions/latest/download";
    inherit hash;
  };

  dashboards = {
    node-exporter  = fetchDashboard { id = 1860; hash = "sha256-pNgn6xgZBEu6LW0lc0cXX2gRkQ8lg/rer34SPE3yEl4="; };
  };

  # ── Scrape targets ────────────────────────────────────────────────────────
  # Add new machines here when provisioned. Each entry becomes a labeled
  # Prometheus target for both node_exporter and cAdvisor jobs.
  nodes = {
    trigkey         = "127.0.0.1";
    docker-services = "10.0.100.10";
  };

  mkTargets = port: lib.mapAttrsToList (name: addr: {
    targets = [ "${addr}:${toString port}" ];
    labels  = { instance = name; };
  }) nodes;
in
{
  # ── Prometheus ────────────────────────────────────────────────────────────
  services.prometheus = {
    enable        = true;
    port          = 9090;
    retentionTime = "30d";

    scrapeConfigs = [
      {
        job_name        = "node";
        scrape_interval = "15s";
        static_configs  = mkTargets 9100;
      }
      {
        job_name        = "cadvisor";
        scrape_interval = "15s";
        static_configs  = mkTargets 9101;
      }
    ];
  };

  # ── Grafana ───────────────────────────────────────────────────────────────
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3000;
      };

      security = {
        admin_user     = "admin";
        admin_password = "$__env{GF_SECURITY_ADMIN_PASSWORD}";
      };
    };

    provision = {
      # ── Datasources ───────────────────────────────────────────────────────
      datasources.settings.datasources = [
        {
          name      = "Prometheus";
          type      = "prometheus";
          url       = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
        }
      ];

      # ── Dashboards ────────────────────────────────────────────────────────
      # Drop JSON files into hosts/optional/dashboards/ to provision them.
      # allowUiUpdates = false keeps Grafana from drifting from the declared state.
      dashboards.settings.providers = [
        {
          name              = "default";
          options.path      = "/etc/grafana/dashboards";
          allowUiUpdates    = false;
          disableDeletion   = true;
        }
      ];
    };
  };

  environment.etc = lib.mapAttrs' (name: src: lib.nameValuePair
    "grafana/dashboards/${name}.json"
    { source = src; }
  ) dashboards;

  networking.firewall.allowedTCPPorts = [ 3000 9090 ];

  # Grafana must start after sops has decrypted the admin password
  systemd.services.grafana = {
    after          = [ "sops-nix.service" ];
    wants          = [ "sops-nix.service" ];
    serviceConfig.EnvironmentFile = config.sops.secrets."grafana/env".path;
  };
}
