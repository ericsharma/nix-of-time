{ config, pkgs, ... }:

let
  steam = "${config.programs.steam.package}/bin/steam";
in
{
  # ── Steam (games through Proton, played over Moonlight) ──────────────────────
  # Runs inside the headless sway session (./sunshine.nix), through Xwayland.
  # GTA V: story mode only; GTA Online's BattlEye blocks Linux.
  # Vega 8 iGPU: 720p low/normal is the target, and Sunshine's encode shares it.
  #
  # Library: add /mnt/backup/steam-library in Steam → Settings → Storage. The
  # NVMe holds /data and a 110 GB game would trip the 15% disk alert there.
  # The T7 is the backup disk, but has ~700 GB free; restic's free-space alert
  # (optional/monitoring.nix) covers it. Games are not backed up.
  programs.steam.enable = true;

  # Created by hand here, not tmpfiles: tmpfiles runs before the T7 mounts and
  # would create the directory on the NVMe under the mount point.
  systemd.services.steam-library-dir = {
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = "/mnt/backup";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -d -m 0755 -o eric -g users /mnt/backup/steam-library";
    };
  };

  # Big Picture is the controller-friendly UI. detached: steam forks and exits
  # its launcher, so Sunshine must not treat that exit as the app ending.
  services.sunshine.applications.apps = [
    {
      name = "Steam";
      detached = [ "${steam} -gamepadui" ];
      prep-cmd = [
        {
          do = "";
          undo = "${steam} -shutdown";
        }
      ];
    }
  ];
}
