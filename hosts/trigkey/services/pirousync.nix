{ config, pkgs, pirousync, ... }:

let
  # Build the image from the flake input source.
  # We copy to a temp dir because the Nix store is read-only and the
  # Dockerfile expects a writable build context (writes .env, node_modules, etc.).
  pirousync-build = pkgs.writeShellScript "pirousync-build" ''
    set -euo pipefail
    BUILDDIR=$(mktemp -d)
    trap "rm -rf $BUILDDIR" EXIT

    cp -r ${pirousync}/. "$BUILDDIR/"
    chmod -R u+w "$BUILDDIR"

    # Inject secrets — .env is read by Vite at build time (VITE_* vars baked
    # into the bundle) and copied into the runner image for the S3 proxy.
    cp ${config.sops.secrets."pirousync/env".path} "$BUILDDIR/.env"

    podman build -t localhost/pirousync:latest "$BUILDDIR"
  '';
in
{
  # ── PiroueSync (synchronized ballet class music player) ─────────────────────
  # Port: 4203
  # Secrets: /run/secrets/pirousync/env (see docs/secrets.md)

  sops.secrets."pirousync/env" = {};

  # Build the container image from source before starting the service.
  # When the flake input is updated (nix flake update pirousync + nixos-rebuild),
  # the store path in the script changes, NixOS restarts this service, and the
  # image is rebuilt automatically.
  systemd.services.pirousync-build = {
    description = "Build PiroueSync container image from source";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    path        = [ config.virtualisation.podman.package ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart       = pirousync-build;
    };
  };

  virtualisation.oci-containers.containers.pirousync = {
    image        = "localhost/pirousync:latest";
    ports        = [ "127.0.0.1:4203:4173" ];
    extraOptions = [ "--pull=never" ];
  };

  # Ensure the image is built before the container starts.
  systemd.services.podman-pirousync = {
    after    = [ "pirousync-build.service" ];
    requires = [ "pirousync-build.service" ];
  };
}
