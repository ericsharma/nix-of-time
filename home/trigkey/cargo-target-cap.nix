{ pkgs, ... }:

# Rust build caches must not fill trigkey's root disk. On 2026-10-28
# ~/etd/target reached 136 GB and left 232 MB free (debug builds of etd's
# tests add up fast).
#
# cargo-target-cap.timer: once a day at 05:00 (after the 01:30–04:30
# backups), each ~/<project>/target next to a Cargo.toml that is over the
# limit loses its debug/ folder. release/ stays; the next build makes
# debug/ again (about 2 minutes for etd).
#
# NOT backed up — build output only.
let
  limitGB = 40;
  cap = pkgs.writeShellApplication {
    name = "cargo-target-cap";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      for toml in "$HOME"/*/Cargo.toml; do
        target=$(dirname "$toml")/target
        [ -d "$target/debug" ] || continue
        gb=$(du -s --block-size=1G "$target" | cut -f1)
        if [ "$gb" -gt ${toString limitGB} ]; then
          echo "$target: $gb GB, over ${toString limitGB} GB: removing debug/"
          rm -rf "$target/debug"
        else
          echo "$target: $gb GB"
        fi
      done
    '';
  };
in
{
  systemd.user.services.cargo-target-cap = {
    Unit.Description = "Remove the debug builds of Rust projects over ${toString limitGB} GB";
    Service = {
      Type = "oneshot";
      ExecStart = "${cap}/bin/cargo-target-cap";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.user.timers.cargo-target-cap = {
    Unit.Description = "Keep Rust build caches under ${toString limitGB} GB, daily";
    Timer = {
      OnCalendar = "*-*-* 05:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
