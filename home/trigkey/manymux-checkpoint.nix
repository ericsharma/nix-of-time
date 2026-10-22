{ pkgs, ... }:

# Sessions come back after a reboot: what tmux-resurrect and continuum did for
# the tmux workspace (tmux-persist.nix). trigkey is the client that sees every
# machine (`mm hosts`), so the checkpoint is taken here, for all of them:
# ~/.config/manymux/checkpoint.toml. Claude sessions come back with
# `claude --continue` in the same directory; shells as login shells there.
#
# - manymux-checkpoint.timer: every 15 minutes, keep a dated copy of the last
#   checkpoint, then save a new one. No save while no session runs anywhere
#   (a node that just started), so an empty node cannot overwrite a good file.
# - manymux-restore.service: once when trigkey starts. A restore leaves every
#   session that still runs alone, so it only puts back trigkey's own (and
#   another machine's, if it went down too).
#
# After gmktec or the m1-mini alone reboots: `mm checkpoint restore --host <it>`.
# An older checkpoint: copy one from ~/.local/state/manymux/checkpoints/ over
# ~/.config/manymux/checkpoint.toml, then `mm checkpoint restore`.
#
# NOT backed up — the checkpoints are rewritten every 15 minutes.
let
  copies = 96; # one day of 15-minute copies
  save = pkgs.writeShellApplication {
    name = "manymux-checkpoint-save";
    runtimeInputs = [
      pkgs.manymux
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      file=$HOME/.config/manymux/checkpoint.toml
      dir=''${XDG_STATE_HOME:-$HOME/.local/state}/manymux/checkpoints
      if [ "$(mm ls 2>/dev/null)" = "no sessions" ]; then
        echo "no sessions running; keeping the last checkpoint"
        exit 0
      fi
      mkdir -p "$dir"
      if [ -f "$file" ]; then
        cp "$file" "$dir/$(date +%Y%m%d-%H%M).toml"
        # Dated names sort by time: newest first, remove all after the first ${toString copies}.
        find "$dir" -maxdepth 1 -name '*.toml' | sort -r | tail -n +${toString (copies + 1)} | xargs -r rm -f
      fi
      mm checkpoint save
    '';
  };
  restore = pkgs.writeShellApplication {
    name = "manymux-restore";
    runtimeInputs = [ pkgs.manymux ];
    text = ''
      # The node may still be starting.
      for _ in $(seq 30); do
        mm ls >/dev/null 2>&1 && break
        sleep 1
      done
      mm checkpoint show
      mm checkpoint restore
    '';
  };
  # The units run `ssh <host> mm agent` for the other machines.
  path = "PATH=${pkgs.openssh}/bin:/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin";
in
{
  systemd.user.services.manymux-checkpoint = {
    Unit.Description = "Save the manymux sessions of every machine";
    Service = {
      Type = "oneshot";
      ExecStart = "${save}/bin/manymux-checkpoint-save";
      Environment = [ path ];
    };
  };

  systemd.user.timers.manymux-checkpoint = {
    Unit.Description = "Save the manymux sessions every 15 minutes";
    Timer = {
      OnBootSec = "15min";
      OnUnitActiveSec = "15min";
    };
    Install.WantedBy = [ "timers.target" ];
  };

  systemd.user.services.manymux-restore = {
    Unit = {
      Description = "Start the saved manymux sessions again after a reboot";
      After = [ "manymux.service" ];
      Requires = [ "manymux.service" ];
      # Once per boot. Not on a deploy: a restore while everything runs
      # would do nothing, but it has no business running then.
      X-RestartIfChanged = false;
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${restore}/bin/manymux-restore";
      Environment = [ path ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
