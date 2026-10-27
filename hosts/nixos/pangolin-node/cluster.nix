{
  config,
  lib,
  pkgs,
  ...
}:

# Pangolin Enterprise Edition as a cluster node (docs/plans/pangolin-cluster.md),
# after upstream's config/ha-reference. State is shared: PostgreSQL + Valkey
# on trigkey over wg-pangolin (trigkey/pangolin-db.nix). Each node runs its own
# Pangolin, Gerbil and Traefik.
#
# Differences from the reference, and why:
# - No load balancer. The dashboard host is in Gerbil's LOCAL_OVERRIDES, so the
#   SNI proxy hands it to this node's Traefik, which gets the certificate from
#   Let's Encrypt itself (Cloudflare DNS-01, as on the CE node).
# - Badger is a local plugin (Traefik's download fails its integrity check).
# - MaxMind databases come from services.geoipupdate, not by hand.
# - Secrets come from the environment (sops template), never config.yml.
let
  pangolinImage = "docker.io/fosrl/pangolin:ee-postgresql-1.25.3";
  gerbilImage = "docker.io/fosrl/gerbil:1.5.2";
  traefikImage = "docker.io/traefik:v3.7.16";
  badgerSrc = pkgs.fetchFromGitHub {
    owner = "fosrl";
    repo = "badger";
    rev = "v1.8.0";
    hash = "sha256-EOTti6Ais9RUnBVK35cysHPONR30oVR6fd3rDlYW1GI=";
  };

  # The production dashboard; every Newt site dials it (its endpoint setting).
  dashboard = "pangolin.ericsharma.xyz";

  # Public IPs of every node: Gerbil trusts PROXY protocol only from these.
  nodes = {
    racknerd-pangolin = "172.245.86.223";
    racknerd = "198.46.199.125";
  };
  name = config.networking.hostName;
  publicIp = nodes.${name};
  wgIp = lib.removeSuffix "/24" (
    builtins.head config.networking.wireguard.interfaces.wg-pangolin.ips
  );

  dataDir = "/var/lib/pangolin-cluster";
  geoipDir = config.services.geoipupdate.settings.DatabaseDirectory;
  podman = "${config.virtualisation.podman.package}/bin/podman";
  yaml = pkgs.formats.yaml { };

  pangolinConfig = yaml.generate "config.yml" {
    gerbil = {
      start_port = 51820;
      base_endpoint = publicIp;
      exit_node_name = name;
    };
    app = {
      dashboard_url = "https://${dashboard}";
      log_level = "info";
    };
    traefik = {
      # Wireguard and local sites are not supported in a cluster.
      site_types = [ "newt" ];
      # Pangolin writes routers and certificates to /var/dynamic and
      # /var/certificates; Traefik reads them from there.
      file_mode = true;
    };
    server = {
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
      maxmind_db_path = "/geoip/GeoLite2-Country.mmdb";
      maxmind_asn_path = "/geoip/GeoLite2-ASN.mmdb";
    };
    flags = {
      require_email_verification = false;
      disable_signup_without_invite = true;
      disable_user_create_org = false;
      # As the reference. Whether raw TCP works in a cluster is a phase A
      # question (production has one on :5432).
      allow_raw_resources = false;
      enable_acme_cert_sync = false;
      disable_local_sites = true;
      disable_basic_wireguard_sites = true;
      # Domains live in the database and resolve through Pangolin's DNS.
      disable_config_managed_domains = true;
      # REST API on :3003 for sites, domains, resources and blueprints. Not
      # published: called inside the container (podman exec … curl
      # localhost:3003) with the key in pangolin.yaml (pangolin-api.key).
      enable_integration_api = true;
    };
  };

  privateConfig = yaml.generate "privateConfig.yml" {
    app = {
      region = name;
      identity_provider_mode = "org";
    };
    redis = {
      host = "10.100.0.1";
      port = 6379;
    };
    flags = {
      enable_redis = true;
      use_pangolin_dns = true;
    };
    acme = {
      cert_mode = "pangolin";
      contact_email = "contact@ericsharma.xyz";
      # Only ONE node in the cluster may be the ACME client: racknerd. It
      # answers DNS-01 through Pangolin's DNS (_acme-challenge.<zone> CNAMEs
      # in Cloudflare → _acme-challenge.<domainId>.cname.ericsharma.xyz) and
      # stores the certificates, encrypted, in PostgreSQL for every node.
      enable_acme_client = name == "racknerd";
    };
    dns = {
      enabled = true;
      nameserver_name = "ns.ericsharma.xyz";
      cname_extension = "cname.ericsharma.xyz";
    };
  };

  traefikStatic = yaml.generate "traefik_config.yml" {
    providers.file = {
      directory = "/var/dynamic";
      watch = true;
    };
    experimental.localPlugins.badger.moduleName = "github.com/fosrl/badger";
    log = {
      level = "INFO";
      format = "common";
    };
    # For the dashboard only; resource certificates come from Pangolin.
    certificatesResolvers.letsencrypt.acme = {
      dnsChallenge.provider = "cloudflare";
      email = "contact@ericsharma.xyz";
      storage = "/letsencrypt/acme.json";
      caServer = "https://acme-v02.api.letsencrypt.org/directory";
    };
    entryPoints = {
      web.address = ":80";
      websecure = {
        address = ":443";
        # Every connection arrives from Gerbil's SNI proxy.
        proxyProtocol.trustedIPs = [
          "0.0.0.0/0"
          "::1/128"
        ];
        transport.respondingTimeouts.readTimeout = "30m";
        http.encodedCharacters = {
          allowEncodedSlash = true;
          allowEncodedQuestionMark = true;
        };
      };
      dashboard.address = ":3000";
      dns.address = ":53/udp";
    };
    serversTransport.insecureSkipVerify = true;
    ping.entryPoint = "web";
  };

  dashboardRouter = rule: service: {
    inherit rule service;
    entryPoints = [ "websecure" ];
    middlewares = [ "badger" ];
    tls.certResolver = "letsencrypt";
  };

  # Copied into /var/dynamic next to the files Pangolin writes there.
  traefikDynamic = yaml.generate "nix.yml" {
    http = {
      middlewares = {
        badger.plugin.badger.disableForwardAuth = true;
        redirect-to-https.redirectScheme.scheme = "https";
      };
      routers = {
        dashboard-redirect = {
          rule = "Host(`${dashboard}`)";
          service = "next-service";
          entryPoints = [ "web" ];
          middlewares = [ "redirect-to-https" ];
        };
        dashboard-next = dashboardRouter "Host(`${dashboard}`) && !PathPrefix(`/api/v1`)" "next-service";
        dashboard-api = dashboardRouter "Host(`${dashboard}`) && PathPrefix(`/api/v1`)" "api-service";
        dashboard-ws = dashboardRouter "Host(`${dashboard}`)" "api-service";
      };
      services = {
        next-service.loadBalancer.servers = [ { url = "http://pangolin:3002"; } ];
        api-service.loadBalancer.servers = [ { url = "http://pangolin:3000"; } ];
      };
    };
    tcp.serversTransports = {
      pp-transport-v1.proxyProtocol.version = 1;
      pp-transport-v2.proxyProtocol.version = 2;
    };
    udp = {
      routers.dns-router = {
        entryPoints = [ "dns" ];
        service = "dns-service";
      };
      services.dns-service.loadBalancer.servers = [ { address = "pangolin:53"; } ];
    };
  };

  traefikDir = pkgs.runCommand "traefik-config" { } ''
    mkdir $out
    cp ${traefikStatic} $out/traefik_config.yml
  '';
in
{
  sops.secrets."pangolin/env" = { };
  sops.secrets."traefik/env" = { };
  sops.secrets."pangolin-db/password" = { };
  sops.secrets."pangolin-redis/password" = { };
  sops.secrets."maxmind/license_key" = { };

  sops.templates."pangolin-cluster.env".content = ''
    ${config.sops.placeholder."pangolin/env"}
    POSTGRES_CONNECTION_STRING=postgresql://pangolin:${
      config.sops.placeholder."pangolin-db/password"
    }@10.100.0.1:5432/pangolin
    REDIS_PASSWORD=${config.sops.placeholder."pangolin-redis/password"}
  '';

  services.geoipupdate = {
    enable = true;
    settings = {
      AccountID = 1436782;
      LicenseKey._secret = config.sops.secrets."maxmind/license_key".path;
      EditionIDs = [
        "GeoLite2-Country"
        "GeoLite2-ASN"
      ];
    };
  };

  boot.kernelModules = [ "wireguard" ];

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [
    53 # Pangolin's DNS server (ns.ericsharma.xyz)
    51820 # Gerbil: Newt sites
    21820 # Gerbil: relay
  ];
  # Gerbil's node API: the other nodes only.
  networking.firewall.interfaces.wg-pangolin.allowedTCPPorts = [ 3004 ];

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 root root -"
    "d ${dataDir}/certificates 0700 root root -"
    "d ${dataDir}/dynamic 0755 root root -"
    "d ${dataDir}/letsencrypt 0700 root root -"
  ];

  virtualisation.oci-containers.containers = {
    pangolin = {
      image = pangolinImage;
      volumes = [
        "${dataDir}:/app/config"
        "${pangolinConfig}:/app/config/config.yml:ro"
        "${privateConfig}:/app/config/privateConfig.yml:ro"
        "${dataDir}/certificates:/var/certificates"
        "${dataDir}/dynamic:/var/dynamic"
        "${geoipDir}:/geoip:ro"
      ];
      environmentFiles = [ config.sops.templates."pangolin-cluster.env".path ];
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
        "--reachableAt=http://${wgIp}:3004"
        "--generateAndSaveKeyTo=/var/config/key"
        "--remoteConfig=http://pangolin:3001/api/v1/"
      ];
      environment = {
        TRUSTED_UPSTREAMS = lib.concatStringsSep "," (lib.attrValues nodes);
        # Only the env var works: the flag is registered only when it is set.
        LOCAL_OVERRIDES = dashboard;
      };
      volumes = [ "${dataDir}:/var/config" ];
      ports = [
        "51820:51820/udp"
        "21820:21820/udp"
        # Public IP only: Podman's aardvark-dns holds 53 on the network's
        # gateway, so a wildcard bind fails "address already in use".
        "${publicIp}:53:53/udp"
        "443:8443" # Gerbil's SNI proxy; it hands TLS to Traefik or another node
        "80:80"
        "${wgIp}:3004:3004" # node API, WireGuard only
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
        "${dataDir}/certificates:/var/certificates:ro"
        "${dataDir}/dynamic:/var/dynamic:ro"
        "${dataDir}/letsencrypt:/letsencrypt"
      ];
      environmentFiles = [ config.sops.secrets."traefik/env".path ];
      dependsOn = [ "gerbil" ];
      extraOptions = [ "--network=container:gerbil" ];
    };
  };

  systemd.services.podman-pangolin = {
    # The MaxMind databases must exist before Pangolin reads them.
    wants = [ "geoipupdate.service" ];
    after = [ "geoipupdate.service" ];
    preStart = ''
      ${podman} network exists pangolin || ${podman} network create pangolin
    '';
  };

  # Our routes (dashboard, DNS) next to the files Pangolin writes. Copied at
  # every start: a tmpfiles `C+` rule left a stale copy on one node when the
  # dashboard name changed. A new file changes this unit, so Traefik restarts.
  systemd.services.podman-traefik.preStart = ''
    install -m 0444 ${traefikDynamic} ${dataDir}/dynamic/nix.yml
  '';

  systemd.services.podman-gerbil = {
    # Port 3004 binds the WireGuard address, so the interface must exist.
    after = [ "wireguard-wg-pangolin.service" ];
    requires = [ "wireguard-wg-pangolin.service" ];
    preStart = ''
      until ${podman} healthcheck run pangolin >/dev/null 2>&1; do
        sleep 2
      done
    '';
    # Same stale-UDP problem as the CE node (pangolin.nix).
    postStart = ''
      ${pkgs.conntrack-tools}/bin/conntrack -D -p udp --orig-port-dst 51820 || true
      ${pkgs.conntrack-tools}/bin/conntrack -D -p udp --orig-port-dst 21820 || true
    '';
  };
}
