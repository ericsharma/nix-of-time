{ lib, pkgs, ... }:

let
  incus = "${pkgs.incus}/bin/incus";

  # Helper to declare an incus instance that is launched if it doesn't exist
  mkInstance = { name, image, extraArgs ? "", staticIp ? null, diskDevices ? {} }: {
    "incus-${name}" = {
      after       = [ "incus.service" "incus-preseed.service" ];
      wantedBy    = [ "multi-user.target" ];
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ${incus} info ${name} &>/dev/null; then
          ${incus} launch ${image} ${name} ${extraArgs}
        else
          ${incus} start ${name} 2>/dev/null || true
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
  systemd.services = lib.mkMerge [
    (mkInstance { name = "alpine"; image = "images:alpine/edge"; })
    (mkInstance {
      name      = "docker-services";
      image     = "images:nixos/25.11";
      extraArgs = "-c security.nesting=true";
      staticIp  = "10.0.100.10";
      diskDevices = {
        koito     = { source = "/srv/docker-services/koito";            path = "/srv/koito"; };
        karakeep  = { source = "/srv/docker-services/karakeep";         path = "/srv/karakeep"; };
        dawarich  = { source = "/srv/docker-services/dawarich";         path = "/srv/dawarich"; };
        periphery = { source = "/srv/docker-services/periphery/komodo"; path = "/etc/komodo"; };
      };
    })
  ];
}
