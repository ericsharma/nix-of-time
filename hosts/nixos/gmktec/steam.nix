{ config, pkgs, ... }:

let
  steam = "${config.programs.steam.package}/bin/steam";
  # Workspace 2 is Steam's (sway rules in ./sunshine.nix); 1 is Pokémon
  # Automation and the Switch player. Switch back on quit so the next app
  # starts on the screen it expects.
  workspace = n: "${pkgs.sway}/bin/swaymsg -q workspace ${toString n}";
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

  # The firmware holds the 5825U at 15 W, and a game pins the Vega 8 at
  # ~1.1 GHz of its 2 GHz. 25 W is the chip's upper cTDP: GTA V then runs the
  # iGPU at ~1.7 GHz, 76 °C (2026-11-24). The SMU forgets the limits on reboot
  # and on resume, so set them again after both. No ryzen_smu module needed:
  # ryzenadj falls back to /dev/mem.
  systemd.services.apu-power-limit = {
    wantedBy = [
      "multi-user.target"
      "post-resume.target"
    ];
    after = [ "post-resume.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ryzenadj}/bin/ryzenadj --stapm-limit=25000 --slow-limit=25000 --fast-limit=28000 --tctl-temp=90";
    };
  };

  # Controllers plugged into this box. No login seat here, so logind never
  # grants eric the uaccess ACL a desktop would; Steam reads pads through both
  # evdev and hidraw. 3537 is GameSir (its 2.4 GHz dongle). Add a vendor line
  # for another brand whose pad Steam lists as unusable.
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", OWNER="eric"
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3537", OWNER="eric"
  '';

  # Big Picture is the controller-friendly UI. detached: steam forks and exits
  # its launcher, so Sunshine must not treat that exit as the app ending.
  services.sunshine.applications.apps = [
    {
      name = "Steam";
      detached = [ "${steam} -gamepadui" ];
      prep-cmd = [
        {
          do = workspace 2;
          undo = "${steam} -shutdown";
        }
        {
          do = "";
          undo = workspace 1;
        }
      ];
    }
  ];
}
