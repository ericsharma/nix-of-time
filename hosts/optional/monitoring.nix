{ config, lib, pkgs, ... }:

let
  dashboards = {
    node-exporter  = ./dashboards/node-exporter.json;
    airgradient    = ./dashboards/airgradient.json;
  };

  # ── AirGradient JSON exporter config ─────────────────────────────────────
  jsonExporterConfig = pkgs.writeText "json-exporter-config.yml" (builtins.toJSON {
    modules.airgradient.metrics = [
      { name = "airgradient_pm01";       path = "{ .pm01 }";       help = "PM1.0 µg/m³";           valuetype = "gauge"; }
      { name = "airgradient_pm02";       path = "{ .pm02 }";       help = "PM2.5 µg/m³";           valuetype = "gauge"; }
      { name = "airgradient_pm10";       path = "{ .pm10 }";       help = "PM10 µg/m³";            valuetype = "gauge"; }
      { name = "airgradient_rco2";       path = "{ .rco2 }";       help = "CO2 ppm";               valuetype = "gauge"; }
      { name = "airgradient_atmp";       path = "{ .atmp }";       help = "Temperature °C";        valuetype = "gauge"; }
      { name = "airgradient_rhum";       path = "{ .rhum }";       help = "Relative humidity %";    valuetype = "gauge"; }
      { name = "airgradient_tvoc_index"; path = "{ .tvocIndex }";  help = "VOC index";             valuetype = "gauge"; }
      { name = "airgradient_nox_index";  path = "{ .noxIndex }";   help = "NOx index";             valuetype = "gauge"; }
      { name = "airgradient_wifi";       path = "{ .wifi }";       help = "WiFi signal strength";  valuetype = "gauge"; }
    ];
  });

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

    exporters.json = {
      enable     = true;
      port       = 7979;
      configFile = jsonExporterConfig;
    };

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
      {
        job_name        = "airgradient";
        scrape_interval = "30s";
        metrics_path    = "/probe";
        params          = { module = [ "airgradient" ]; };
        static_configs  = [{
          targets = [ "http://192.168.0.96/measures/current" ];
          labels  = { instance = "airgradient-one"; };
        }];
        relabel_configs = [
          { source_labels = [ "__address__" ];
            target_label  = "__param_target"; }
          { target_label = "__address__";
            replacement  = "127.0.0.1:7979"; }
        ];
      }
      {
        job_name       = "json-exporter";
        static_configs = [{ targets = [ "127.0.0.1:7979" ]; }];
      }
    ];
  };

  # ── Grafana ───────────────────────────────────────────────────────────────
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
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

  # Grafana must start after sops has decrypted the admin password
  sops.secrets."grafana/env" = {
    owner = "grafana";
    group = "grafana";
  };

  systemd.services.grafana = {
    after          = [ "sops-nix.service" ];
    wants          = [ "sops-nix.service" ];
    serviceConfig.EnvironmentFile = config.sops.secrets."grafana/env".path;
  };
}
