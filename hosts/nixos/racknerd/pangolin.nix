{
  config,
  pkgs,
  ...
}:

# Pangolin (Community Edition) + Gerbil + Traefik, as the official images.
# Not nixpkgs' services.pangolin: its package trails upstream (1.24.0 on
# unstable when this was written) and a Pangolin database cannot go back a
# version. Clustering (Redis + Postgres) is Enterprise-only: switching means
# the `ee-` image tag and a database move — see docs/services/pangolin.md.
#
# Upgrade: bump the tags and badgerSrc below, read the release notes in between (Gerbil and
# Badger versions move with Pangolin's installer: install/Makefile upstream).
#
# Data: /var/lib/pangolin (db/db.sqlite, Gerbil's WireGuard `key`, letsencrypt/).
# Secrets: secrets/racknerd.yaml → pangolin.env (SERVER_SECRET), traefik.env
# (CLOUDFLARE_DNS_API_TOKEN).
let
  pangolinImage = "docker.io/fosrl/pangolin:1.25.3";
  gerbilImage = "docker.io/fosrl/gerbil:1.5.2";
  traefikImage = "docker.io/traefik:v3.7.16";
  # Badger is Pangolin's auth middleware, a Traefik plugin. Loaded as a local
  # plugin from this pinned source: Traefik's own download of v1.8.0 fails
  # "plugin integrity check failed", and a local plugin needs no network.
  badgerSrc = pkgs.fetchFromGitHub {
    owner = "fosrl";
    repo = "badger";
    rev = "v1.8.0";
    hash = "sha256-EOTti6Ais9RUnBVK35cysHPONR30oVR6fd3rDlYW1GI=";
  };

  dataDir = "/var/lib/pangolin";
  podman = "${config.virtualisation.podman.package}/bin/podman";
  yaml = pkgs.formats.yaml { };

  dashboard = "pangolin.ericsharma.xyz";

  # No secrets in here: SERVER_SECRET comes from the environment
  # (getEnvOrYaml in Pangolin's readConfigFile.ts). The server admin already
  # exists in the database, so the old `users.server_admin` block is gone.
  pangolinConfig = yaml.generate "config.yml" {
    app = {
      dashboard_url = "https://${dashboard}";
      log_level = "info";
      save_logs = false;
    };
    # cert_resolver must name a resolver in traefikStatic below.
    domains = {
      domain1 = {
        base_domain = "ericsharma.xyz";
        cert_resolver = "letsencrypt";
        prefer_wildcard_cert = true;
      };
      domain2 = {
        base_domain = "companypro.com";
        cert_resolver = "letsencrypt-companypro";
        prefer_wildcard_cert = true;
      };
      domain3 = {
        base_domain = "blindjoe.xyz";
        cert_resolver = "letsencrypt";
        prefer_wildcard_cert = true;
      };
      domain4 = {
        base_domain = "libertygifs.xyz";
        cert_resolver = "letsencrypt-libertygifs";
        prefer_wildcard_cert = true;
      };
      domain5 = {
        base_domain = "bellewatsonstudio.com";
        cert_resolver = "letsencrypt";
        prefer_wildcard_cert = true;
      };
    };
    server = {
      external_port = 3000;
      internal_port = 3001;
      next_port = 3002;
      internal_hostname = "pangolin";
      cors = {
        origins = [ "https://${dashboard}" ];
        methods = [
          "GET"
          "POST"
          "PUT"
          "DELETE"
          "PATCH"
        ];
        allowed_headers = [
          "X-CSRF-Token"
          "Content-Type"
        ];
        credentials = false;
      };
    };
    traefik = {
      cert_resolver = "letsencrypt";
      http_entrypoint = "web";
      https_entrypoint = "websecure";
    };
    gerbil = {
      start_port = 51820;
      base_endpoint = dashboard;
      use_subdomain = false;
      block_size = 24;
      site_block_size = 30;
      # Must not change: existing sites hold addresses from this range.
      subnet_group = "100.89.137.0/20";
    };
    rate_limits.global = {
      window_minutes = 1;
      max_requests = 500;
    };
    flags = {
      require_email_verification = false;
      disable_signup_without_invite = true;
      disable_user_create_org = false;
      # Raw TCP/UDP resources: the tcp-5432 entrypoint below serves one.
      allow_raw_resources = true;
      allow_base_domain_resources = true;
    };
  };

  # Every zone is on Cloudflare; one token (traefik.env) covers all of them.
  # Each resolver keeps its own storage file so existing certificates carry over.
  cloudflareResolver = email: storage: {
    acme = {
      dnsChallenge.provider = "cloudflare";
      inherit email storage;
      caServer = "https://acme-v02.api.letsencrypt.org/directory";
    };
  };

  traefikStatic = yaml.generate "traefik_config.yml" {
    api = {
      # Reachable only inside Gerbil's network namespace; port 8080 is not
      # published.
      insecure = true;
      dashboard = true;
    };
    providers = {
      http = {
        endpoint = "http://pangolin:3001/api/v1/traefik-config";
        pollInterval = "5s";
      };
      file.filename = "/etc/traefik/dynamic_config.yml";
    };
    # Read from /plugins-local/src/<moduleName> (mounted below).
    experimental.localPlugins.badger.moduleName = "github.com/fosrl/badger";
    # No filePath: Traefik logs to stdout, so the journal rotates them.
    log = {
      level = "INFO";
      format = "common";
    };
    certificatesResolvers = {
      letsencrypt = cloudflareResolver "contact@ericsharma.xyz" "/letsencrypt/acme.json";
      letsencrypt-companypro = cloudflareResolver "eric@algonaut.ca" "/letsencrypt/acme-companypro.json";
      letsencrypt-libertygifs = cloudflareResolver "contact@ericsharma.xyz" "/letsencrypt/acme-libertygifs.json";
    };
    entryPoints = {
      web.address = ":80";
      websecure = {
        address = ":443";
        transport.respondingTimeouts.readTimeout = "30m";
        http3.advertisedPort = 443;
        http = {
          tls.certResolver = "letsencrypt";
          encodedCharacters = {
            allowEncodedSlash = true;
            allowEncodedQuestionMark = true;
          };
        };
      };
      # A raw TCP resource in Pangolin is bound to this entrypoint. It is not a
      # database on this host.
      tcp-5432.address = ":5432/tcp";
    };
    serversTransport.insecureSkipVerify = true;
    ping.entryPoint = "web";
  };

  # The dashboard itself, on two hostnames. Resources come from Pangolin over
  # the http provider, not from this file.
  dashboardRouters = name: host: resolver: {
    "${name}-redirect" = {
      rule = "Host(`${host}`)";
      service = "next-service";
      entryPoints = [ "web" ];
      middlewares = [
        "redirect-to-https"
        "badger"
      ];
    };
    "${name}-next" = {
      rule = "Host(`${host}`) && !PathPrefix(`/api/v1`)";
      service = "next-service";
      entryPoints = [ "websecure" ];
      middlewares = [ "badger" ];
      tls.certResolver = resolver;
    };
    "${name}-api" = {
      rule = "Host(`${host}`) && PathPrefix(`/api/v1`)";
      service = "api-service";
      entryPoints = [ "websecure" ];
      middlewares = [ "badger" ];
      tls.certResolver = resolver;
    };
    "${name}-ws" = {
      rule = "Host(`${host}`)";
      service = "api-service";
      entryPoints = [ "websecure" ];
      middlewares = [ "badger" ];
      tls.certResolver = resolver;
    };
  };

  traefikDynamic = yaml.generate "dynamic_config.yml" {
    http = {
      middlewares = {
        badger.plugin.badger.disableForwardAuth = true;
        redirect-to-https.redirectScheme.scheme = "https";
      };
      routers =
        dashboardRouters "ericsharma" dashboard "letsencrypt"
        // dashboardRouters "companypro" "pangolin.companypro.com" "letsencrypt-companypro";
      services = {
        next-service.loadBalancer.servers = [ { url = "http://pangolin:3002"; } ];
        api-service.loadBalancer.servers = [ { url = "http://pangolin:3000"; } ];
      };
    };
    tcp.serversTransports = {
      pp-transport-v1.proxyProtocol.version = 1;
      pp-transport-v2.proxyProtocol.version = 2;
    };
  };

  # Real files, not a linkFarm: symlinks into /nix/store do not resolve
  # inside the container.
  traefikDir = pkgs.runCommand "traefik-config" { } ''
    mkdir $out
    cp ${traefikStatic} $out/traefik_config.yml
    cp ${traefikDynamic} $out/dynamic_config.yml
  '';
in
{
  sops.secrets."pangolin/env" = { };
  sops.secrets."traefik/env" = { };

  # Gerbil runs WireGuard in the kernel; a container cannot modprobe on NixOS.
  boot.kernelModules = [ "wireguard" ];

  # Podman publishes these (DNAT), so this list records them more than it
  # opens them.
  networking.firewall.allowedTCPPorts = [
    80
    443
    5432
  ];
  networking.firewall.allowedUDPPorts = [
    443 # HTTP/3
    51820 # Gerbil: Newt sites
    21820 # Gerbil: clients (Olm)
  ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 root root -"
    "d ${dataDir}/letsencrypt 0700 root root -"
  ];

  virtualisation.oci-containers.containers = {
    pangolin = {
      image = pangolinImage;
      volumes = [
        "${dataDir}:/app/config"
        "${pangolinConfig}:/app/config/config.yml:ro"
      ];
      environmentFiles = [ config.sops.secrets."pangolin/env".path ];
      extraOptions = [
        "--network=pangolin"
        "--health-cmd=curl -f http://localhost:3001/api/v1/"
        "--health-interval=10s"
        "--health-retries=15"
      ];
    };

    gerbil = {
      image = gerbilImage;
      cmd = [
        "--reachableAt=http://gerbil:3004"
        "--generateAndSaveKeyTo=/var/config/key"
        "--remoteConfig=http://pangolin:3001/api/v1/"
      ];
      volumes = [ "${dataDir}:/var/config" ];
      # Traefik shares this network namespace, so its ports are published here.
      ports = [
        "51820:51820/udp"
        "21820:21820/udp"
        "80:80"
        "443:443"
        "443:443/udp"
        "5432:5432"
      ];
      dependsOn = [ "pangolin" ];
      extraOptions = [
        "--network=pangolin"
        "--cap-add=NET_ADMIN"
        "--cap-add=SYS_MODULE"
      ];
    };

    traefik = {
      image = traefikImage;
      cmd = [ "--configFile=/etc/traefik/traefik_config.yml" ];
      volumes = [
        "${traefikDir}:/etc/traefik:ro"
        "${badgerSrc}:/plugins-local/src/github.com/fosrl/badger:ro"
        "${dataDir}/letsencrypt:/letsencrypt"
      ];
      environmentFiles = [ config.sops.secrets."traefik/env".path ];
      dependsOn = [ "gerbil" ];
      extraOptions = [ "--network=container:gerbil" ];
    };
  };

  # ── Network ──────────────────────────────────────────────────────────────────
  systemd.services.podman-pangolin.preStart = ''
    ${podman} network exists pangolin || ${podman} network create pangolin
  '';

  # ── Gerbil asks Pangolin for its config at start: wait until it answers ──────
  systemd.services.podman-gerbil.preStart = ''
    until ${podman} healthcheck run pangolin >/dev/null 2>&1; do
      sleep 2
    done
  '';
}
