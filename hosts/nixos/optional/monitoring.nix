{
  config,
  lib,
  pkgs,
  inventory,
  ...
}:

let
  dashboards = {
    node-exporter = ./dashboards/node-exporter.json;
    airgradient = ./dashboards/airgradient.json;
    trigkey-overview = ./dashboards/trigkey-overview.json;
    media-storage = ./dashboards/media-storage.json;
    portless-services = ./dashboards/portless-services.json;
  };

  # Home Assistant receives Grafana alerts on a local-only webhook and turns
  # them into a notification. The automation lives in
  # hosts/nixos/optional/homeassistant.nix and must keep this same id.
  #
  # The id is not a credential to anything sensitive, and the automation sets
  # local_only, so only the LAN can post to it. The worst a LAN client can do
  # is create a notification.
  haWebhookId = "grafana-alerts-3f9c1a7e5b";

  # One alert rule, at two severities. The query is the fraction of free space
  # on the filesystem that carries /data, so it keeps working if that ever
  # becomes its own mount.
  freeSpaceRule =
    {
      uid,
      title,
      threshold,
      forDuration,
      severity,
      summary,
    }:
    {
      inherit uid title;
      condition = "C";
      for = forDuration;
      orgId = 1;
      folderUID = "alerts";
      ruleGroup = "storage";
      # "OK" rather than the "NoData" default. A disk rule with NoData→alert
      # fires every time Grafana restarts, because the query window is empty
      # for the first evaluation — a notification that means nothing and trains
      # you to ignore the ones that do. The genuine "gmktec has gone away" case
      # is covered by its own rule below, which is what should carry it.
      noDataState = "OK";
      execErrState = "Error";
      annotations = {
        inherit summary;
        # Links the alert to the Media Storage dashboard, so a notification is
        # one click from the trend that caused it. Grafana rejects the whole
        # provisioning file if only one of these two is set — it fails closed,
        # and Grafana then will not start at all.
        __dashboardUid__ = "media-storage";
        __panelId__ = "5"; # "Free space trend"
      };
      labels = {
        inherit severity;
        host = "gmktec";
      };
      data = [
        {
          refId = "A";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          datasourceUid = "Prometheus";
          model = {
            refId = "A";
            expr = "node_filesystem_avail_bytes{instance=\"gmktec\",mountpoint=\"/\"} / node_filesystem_size_bytes{instance=\"gmktec\",mountpoint=\"/\"} * 100";
            instant = true;
          };
        }
        {
          refId = "B";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          datasourceUid = "__expr__";
          model = {
            refId = "B";
            type = "reduce";
            reducer = "last";
            expression = "A";
          };
        }
        {
          refId = "C";
          relativeTimeRange = {
            from = 600;
            to = 0;
          };
          datasourceUid = "__expr__";
          model = {
            refId = "C";
            type = "threshold";
            expression = "B";
            conditions = [
              {
                evaluator = {
                  type = "lt";
                  params = [ threshold ];
                };
              }
            ];
          };
        }
      ];
    };

  # ── AirGradient JSON exporter config ─────────────────────────────────────
  jsonExporterConfig = pkgs.writeText "json-exporter-config.yml" (
    builtins.toJSON {
      modules.airgradient.metrics = [
        {
          name = "airgradient_pm01";
          path = "{ .pm01 }";
          help = "PM1.0 µg/m³";
          valuetype = "gauge";
        }
        {
          name = "airgradient_pm02";
          path = "{ .pm02 }";
          help = "PM2.5 µg/m³";
          valuetype = "gauge";
        }
        {
          name = "airgradient_pm10";
          path = "{ .pm10 }";
          help = "PM10 µg/m³";
          valuetype = "gauge";
        }
        {
          name = "airgradient_rco2";
          path = "{ .rco2 }";
          help = "CO2 ppm";
          valuetype = "gauge";
        }
        {
          name = "airgradient_atmp";
          path = "{ .atmp }";
          help = "Temperature °C";
          valuetype = "gauge";
        }
        {
          name = "airgradient_rhum";
          path = "{ .rhum }";
          help = "Relative humidity %";
          valuetype = "gauge";
        }
        {
          name = "airgradient_tvoc_index";
          path = "{ .tvocIndex }";
          help = "VOC index";
          valuetype = "gauge";
        }
        {
          name = "airgradient_nox_index";
          path = "{ .noxIndex }";
          help = "NOx index";
          valuetype = "gauge";
        }
        {
          name = "airgradient_wifi";
          path = "{ .wifi }";
          help = "WiFi signal strength";
          valuetype = "gauge";
        }
      ];
    }
  );

  # ── Scrape targets ────────────────────────────────────────────────────────
  # Sourced from inventory.nix at the repo root — add new hosts there and
  # they automatically become labeled Prometheus targets.
  mkTargets =
    port:
    lib.mapAttrsToList (
      name:
      { address, ... }:
      {
        targets = [ "${address}:${toString port}" ];
        labels = {
          instance = name;
        };
      }
    ) inventory.hosts;

  # ── Portless probes ───────────────────────────────────────────────────────
  # One entry per `<alias>.local` name published anywhere in the fleet, flattened
  # out of inventory.hosts.*.portlessAliases. Adding an alias there adds the
  # blackbox module, the scrape target, and the dashboard row in one edit.
  portlessProbes = lib.concatMap (
    hostName:
    lib.mapAttrsToList (alias: port: {
      inherit alias port;
      host = hostName;
      inherit (inventory.hosts.${hostName}) address;
      fqdn = "${alias}.local";
      # An alias may hold dots (`trigkey.finance`). Blackbox module names are
      # free-form, but a dot in one reads as a nested key to anything that
      # later parses the config, so flatten it.
      module = "portless_${lib.replaceStrings [ "." ] [ "_" ] alias}";
    }) inventory.hosts.${hostName}.portlessAliases
  ) (lib.attrNames inventory.hosts);

  # Probes go to the proxy, not to the service port, because that is what the
  # `.local` URL actually exercises: it catches a dead backend (502 from the
  # proxy) *and* a route the daemon has forgotten (404), which a direct port
  # check would miss. The Host header is what portless routes on, so each alias
  # needs its own module — the target URL carries only the host's address.
  blackboxConfig = pkgs.writeText "blackbox-exporter.yml" (
    builtins.toJSON {
      modules = lib.listToAttrs (
        map (
          p:
          lib.nameValuePair p.module {
            prober = "http";
            timeout = "5s";
            http = {
              method = "GET";
              headers.Host = p.fqdn;
              # A LAN UI behind a login answers 401/403 and is still up; the
              # *arrs and Jellyfin answer 200 or a redirect. 502 is left out on
              # purpose — that is portless reporting its backend is gone, which
              # is exactly the "service is down" case this dashboard is for.
              valid_status_codes = [
                200
                204
                301
                302
                303
                307
                308
                401
                403
              ];
              # The redirect target is a *.local name, and blackbox resolves
              # with Go's own resolver, which does not consult nss-mdns. Chasing
              # the redirect would fail on DNS and report a healthy service as
              # down. The 3xx itself is proof enough that the route works.
              follow_redirects = false;
              preferred_ip_protocol = "ip4";
            };
          }
        ) portlessProbes
      );
    }
  );
in
{
  # ── Prometheus ────────────────────────────────────────────────────────────
  services.prometheus = {
    enable = true;
    port = 9090;
    # Keep air-quality (and all other) data forever. Prometheus treats "0" as
    # "unset" and falls back to its 15d default, so we use a huge duration
    # instead. No size-based retention is set, so nothing else prunes the TSDB.
    retentionTime = "100y";

    exporters.json = {
      enable = true;
      port = 7979;
      configFile = jsonExporterConfig;
    };

    # Probes every portless alias in the fleet. Listens on 127.0.0.1 only —
    # Prometheus is the sole client and it runs on this host.
    exporters.blackbox = {
      enable = true;
      port = 9115;
      listenAddress = "127.0.0.1";
      configFile = blackboxConfig;
    };

    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "15s";
        static_configs = mkTargets 9100;
      }
      {
        job_name = "cadvisor";
        scrape_interval = "15s";
        static_configs = mkTargets 9101;
      }
      {
        job_name = "airgradient";
        scrape_interval = "30s";
        metrics_path = "/probe";
        params = {
          module = [ "airgradient" ];
        };
        static_configs = [
          {
            targets = [ "http://192.168.0.96/measures/current" ];
            labels = {
              instance = "airgradient-one";
            };
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:7979";
          }
        ];
      }
      {
        job_name = "json-exporter";
        static_configs = [ { targets = [ "127.0.0.1:7979" ]; } ];
      }
      # ── Portless aliases ──────────────────────────────────────────────────
      # The target is the proxy on each host; the blackbox module carries the
      # Host header that selects the route, so `module` rides along as a label
      # and is relabelled into the query string, then dropped so it does not
      # end up on every series.
      {
        job_name = "portless";
        scrape_interval = "30s";
        metrics_path = "/probe";
        static_configs = map (p: {
          targets = [ "http://${p.address}:${toString inventory.portlessPort}/" ];
          labels = {
            instance = p.host;
            alias = p.fqdn;
            service = p.alias;
            backend_port = toString p.port;
            module = p.module;
          };
        }) portlessProbes;
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "module" ];
            target_label = "__param_module";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:${toString config.services.prometheus.exporters.blackbox.port}";
          }
          {
            regex = "module";
            action = "labeldrop";
          }
        ];
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
        admin_user = "admin";
        admin_password = "$__env{GF_SECURITY_ADMIN_PASSWORD}";
      };
    };

    provision = {
      # ── Datasources ───────────────────────────────────────────────────────
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          # Pinned, not left to Grafana. Without an explicit uid Grafana mints a
          # random one (PBFA97CFB590B2093 here), and everything that addresses
          # the datasource by uid stops resolving. Dashboards survive that
          # because the frontend falls back to a lookup by name; the alert rules
          # below do NOT — they are evaluated server-side, where the uid is the
          # only key. All three rules sat in health=error, "data source not
          # found", from the day they were provisioned, so the disk-full alerts
          # had never once been able to fire. Keep this value in step with
          # `datasourceUid` in the rules and with the dashboard JSON.
          #
          # Pinning this on a Grafana that ALREADY holds a datasource of the
          # same name under a different uid does not migrate — the provisioner
          # exits with "Datasource provisioning error: data source not found"
          # and grafana.service then fails to start at all. A fresh install is
          # fine. The existing box was migrated once, by hand, on 2026-09-10:
          #   systemctl stop grafana
          #   sqlite3 /var/lib/grafana/data/grafana.db \
          #     "update data_source set uid='Prometheus' where name='Prometheus'"
          #   systemctl start grafana
          # Do the same before changing this value again, or add the datasource
          # to `deleteDatasources` for one deploy.
          uid = "Prometheus";
          type = "prometheus";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
        }
      ];

      # ── Dashboards ────────────────────────────────────────────────────────
      # Drop JSON files into hosts/optional/dashboards/ to provision them.
      # allowUiUpdates = false keeps Grafana from drifting from the declared state.
      dashboards.settings.providers = [
        {
          name = "default";
          options.path = "/etc/grafana/dashboards";
          allowUiUpdates = false;
          disableDeletion = true;
        }
      ];

      # ── Alerting ──────────────────────────────────────────────────────────
      # Grafana's own unified alerting, not Alertmanager — there is no
      # Alertmanager on this host and one rule does not justify adding it.
      alerting = {
        contactPoints.settings = {
          apiVersion = 1;
          contactPoints = [
            {
              orgId = 1;
              name = "home-assistant";
              receivers = [
                {
                  uid = "ha-webhook";
                  type = "webhook";
                  settings = {
                    url = "http://127.0.0.1:8123/api/webhook/${haWebhookId}";
                    httpMethod = "POST";
                  };
                }
              ];
            }
          ];
        };

        policies.settings = {
          apiVersion = 1;
          policies = [
            {
              orgId = 1;
              receiver = "home-assistant";
              group_by = [
                "grafana_folder"
                "alertname"
              ];
              # Repeat a still-firing disk alert daily. Often enough not to be
              # forgotten, rare enough not to be trained out of noticing.
              group_wait = "30s";
              group_interval = "5m";
              repeat_interval = "24h";
            }
          ];
        };

        rules.settings = {
          apiVersion = 1;
          groups = [
            {
              orgId = 1;
              name = "storage";
              folder = "alerts";
              interval = "5m";
              rules = [
                (freeSpaceRule {
                  uid = "gmktec-disk-low";
                  title = "gmktec media disk below 15% free";
                  threshold = 15.0;
                  forDuration = "15m";
                  severity = "warning";
                  summary = "gmktec /data is below 15% free. Prune a series or a film in the Media Storage dashboard.";
                })
                (freeSpaceRule {
                  uid = "gmktec-disk-critical";
                  title = "gmktec media disk below 5% free";
                  threshold = 5.0;
                  forDuration = "5m";
                  severity = "critical";
                  summary = "gmktec /data is below 5% free. SABnzbd will pause itself when it runs out.";
                })
                # The counterpart to noDataState = "OK" above: this is what
                # tells you the disk figures have stopped arriving, instead of
                # every disk rule shouting at once.
                {
                  uid = "gmktec-exporter-down";
                  title = "gmktec is not reporting metrics";
                  condition = "C";
                  for = "10m";
                  orgId = 1;
                  folderUID = "alerts";
                  ruleGroup = "storage";
                  noDataState = "Alerting";
                  execErrState = "Error";
                  annotations = {
                    summary = "Prometheus cannot scrape node_exporter on gmktec. Disk figures on the Media Storage dashboard are stale.";
                    __dashboardUid__ = "media-storage";
                    __panelId__ = "9"; # "Metrics age"
                  };
                  labels = {
                    severity = "critical";
                    host = "gmktec";
                  };
                  data = [
                    {
                      refId = "A";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "Prometheus";
                      model = {
                        refId = "A";
                        expr = "up{instance=\"gmktec\",job=\"node\"}";
                        instant = true;
                      };
                    }
                    {
                      refId = "B";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        refId = "B";
                        type = "reduce";
                        reducer = "last";
                        expression = "A";
                      };
                    }
                    {
                      refId = "C";
                      relativeTimeRange = {
                        from = 600;
                        to = 0;
                      };
                      datasourceUid = "__expr__";
                      model = {
                        refId = "C";
                        type = "threshold";
                        expression = "B";
                        conditions = [
                          {
                            evaluator = {
                              type = "lt";
                              params = [ 1.0 ];
                            };
                          }
                        ];
                      };
                    }
                  ];
                }
              ];
            }
          ];
        };
      };
    };
  };

  environment.etc = lib.mapAttrs' (
    name: src: lib.nameValuePair "grafana/dashboards/${name}.json" { source = src; }
  ) dashboards;

  # Grafana must start after sops has decrypted the admin password
  sops.secrets."grafana/env" = {
    owner = "grafana";
    group = "grafana";
  };

  systemd.services.grafana = {
    after = [ "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
    serviceConfig.EnvironmentFile = config.sops.secrets."grafana/env".path;
  };
}
