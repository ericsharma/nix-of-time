{ config, lib, pkgs, ... }:

let
  incus = "${pkgs.incus}/bin/incus";

  # Helper to declare an incus instance that is launched if it doesn't exist
  mkInstance = { name, image, extraArgs ? "", cloudInitFile ? null, staticIp ? null, diskDevices ? {} }: {
    "incus-${name}" = {
      after       = [ "incus.service" "incus-preseed.service" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ${incus} info ${name} &>/dev/null; then
          ${incus} launch ${image} ${name} ${extraArgs} \
            ${lib.optionalString (cloudInitFile != null)
              "-c cloud-init.user-data=\"$(cat ${cloudInitFile})\""}
        fi
        ${lib.optionalString (staticIp != null) ''
          if ! ${incus} config device show ${name} | grep -q "ipv4.address: ${staticIp}"; then
            ${incus} config device override ${name} eth0 ipv4.address=${staticIp} 2>/dev/null || \
            ${incus} config device set ${name} eth0 ipv4.address=${staticIp}
          fi
        ''}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (devName: dev: ''
          if ! ${incus} config device show ${name} 2>/dev/null | grep -q "^${devName}:"; then
            ${incus} config device add ${name} ${devName} disk \
              source=${dev.source} path=${dev.path} shift=true
          fi
        '') diskDevices)}
      '';
    };
  };

  # Path to compose files in the nix store
  composeDir = ./compose;

in
{
  # ── Host data directories (persisted across container recreation) ──────────
  systemd.tmpfiles.rules = [
    "d /srv/docker-services                        0755 root root -"
    "d /srv/docker-services/koito                  0755 root root -"
    "d /srv/docker-services/koito/db               0755 root root -"
    "d /srv/docker-services/koito/data             0755 root root -"
    "d /srv/docker-services/karakeep               0755 root root -"
    "d /srv/docker-services/karakeep/data          0755 root root -"
    "d /srv/docker-services/karakeep/meilisearch   0755 root root -"
    "d /srv/docker-services/dawarich               0755 root root -"
    "d /srv/docker-services/dawarich/db            0755 root root -"
    "d /srv/docker-services/dawarich/shared        0755 root root -"
    "d /srv/docker-services/dawarich/public        0755 root root -"
    "d /srv/docker-services/dawarich/watched       0755 root root -"
    "d /srv/docker-services/dawarich/storage       0755 root root -"
    "d /srv/docker-services/periphery              0755 root root -"
    "d /srv/docker-services/periphery/komodo       0755 root root -"
  ];

  # ── Instances ─────────────────────────────────────────────────────────────
  # Add or remove containers/VMs here.
  # For a VM, add: extraArgs = "--vm"
  systemd.services = lib.mkMerge [
    (mkInstance { name = "alpine"; image = "images:alpine/edge"; })
    (mkInstance {
      name          = "docker-services";
      image         = "images:alpine/edge/cloud";
      cloudInitFile = ./cloud-init/docker-services.yaml;
      staticIp      = "10.169.115.10";
      extraArgs     = "-c security.nesting=true";
      diskDevices   = {
        koito     = { source = "/srv/docker-services/koito";            path = "/srv/koito"; };
        karakeep  = { source = "/srv/docker-services/karakeep";         path = "/srv/karakeep"; };
        dawarich  = { source = "/srv/docker-services/dawarich";         path = "/srv/dawarich"; };
        periphery = { source = "/srv/docker-services/periphery/komodo"; path = "/etc/komodo"; };
      };
    })
    # (mkInstance { name = "ubuntu"; image = "images:ubuntu/24.04"; })
    # (mkInstance { name = "win11";  image = "images:windows/11"; extraArgs = "--vm"; })

    # ── Provision the docker-services container ───────────────────────────
    # Runs after every (re)start of the container. Waits for cloud-init to
    # complete, then pushes compose files and sops-decrypted .env files.
    # This ensures a fully fresh machine works without manual intervention.
    {
      docker-services-provision = {
        description = "Provision docker-services container (compose files + secrets)";
        after  = [ "incus-docker-services.service" ];
        partOf = [ "incus-docker-services.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "eric";
        };
        script = ''
          # Wait for container to be running
          until ${incus} info docker-services 2>/dev/null | grep -q "Status: RUNNING"; do
            sleep 2
          done

          # Wait for cloud-init to finish so all directories exist
          # (exit code 2 means "already done" on some distros, treat as success)
          ${incus} exec docker-services -- cloud-init status --wait || true

          # ── Push compose files ──────────────────────────────────────────
          ${incus} file push ${composeDir}/koito/docker-compose.yml \
            docker-services/srv/compose/koito/docker-compose.yml
          ${incus} file push ${composeDir}/karakeep/docker-compose.yml \
            docker-services/srv/compose/karakeep/docker-compose.yml
          ${incus} file push ${composeDir}/dawarich/docker-compose.yml \
            docker-services/srv/compose/dawarich/docker-compose.yml
          ${incus} file push ${composeDir}/periphery/docker-compose.yml \
            docker-services/srv/compose/periphery/docker-compose.yml

          # ── Push sops-decrypted .env files ──────────────────────────────
          ${incus} file push ${config.sops.secrets."docker-services/koito/env".path} \
            docker-services/srv/compose/koito/.env
          ${incus} file push ${config.sops.secrets."docker-services/karakeep/env".path} \
            docker-services/srv/compose/karakeep/.env
          ${incus} file push ${config.sops.secrets."docker-services/dawarich/env".path} \
            docker-services/srv/compose/dawarich/.env
          ${incus} file push ${config.sops.secrets."docker-services/periphery/env".path} \
            docker-services/srv/compose/periphery/.env

          # ── Start stacks (idempotent) ────────────────────────────────────
          ${incus} exec docker-services -- rc-service docker-stacks start || true
        '';
      };
    }
  ];
}
