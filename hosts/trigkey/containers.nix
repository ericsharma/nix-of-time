{ config, lib, pkgs, ... }:

let
  incus = "${pkgs.incus}/bin/incus";

  # Helper to declare an incus instance that is launched if it doesn't exist
  mkInstance = { name, image, extraArgs ? "" }: {
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
        fi
      '';
    };
  };

in
{
  # ── Instances ─────────────────────────────────────────────────────────────
  # Add or remove containers/VMs here.
  # For a VM, add: extraArgs = "--vm"
  systemd.services = lib.mkMerge [
    (mkInstance { name = "alpine"; image = "images:alpine/edge"; })
    # (mkInstance { name = "ubuntu"; image = "images:ubuntu/24.04"; })
    # (mkInstance { name = "win11";  image = "images:windows/11"; extraArgs = "--vm"; })
  ];
}
