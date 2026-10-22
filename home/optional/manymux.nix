{ pkgs, ... }:

# manymux node (`mm daemon`) as a user service: it owns this machine's
# terminal sessions. The E.T. app reaches them through etd on trigkey, which
# runs `mm agent` here (trigkey) or `ssh <host> mm agent` (other machines).
# Plan: ~/et-ios/docs/PLAN-manymux.md. Package: pkgs/manymux.nix.
#
# --no-notify: these machines have no desktop to raise a notification on.
# Bells reach the phone through etd (it follows trigkey's node) and et-notify.
#
# Data: ~/.config/manymux (the machines to watch). Sessions live in memory.
# NOT backed up — the machine list is two `mm add` lines.
{
  # home.packages: non-interactive ssh on NixOS has /etc/profiles/per-user/*
  # in PATH, so `ssh <host> mm agent` finds it.
  home.packages = [ pkgs.manymux ];

  # The key for manymux's control mode (`mm attach`). Its default, Ctrl-],
  # does not reach trigkey from the laptop's terminal; Ctrl-b (the tmux
  # prefix) does. Pressed twice quickly, it sends one Ctrl-b to the session.
  home.sessionVariables.MM_PREFIX = "C-b";

  systemd.user.services.manymux = {
    Unit = {
      Description = "manymux node: persistent terminal sessions";
      # A restart ends every session on this machine. Never on a deploy; a new
      # binary is picked up by hand with `mm update --keep-sessions`.
      X-RestartIfChanged = false;
    };
    Service = {
      ExecStart = "${pkgs.manymux}/bin/mm daemon --no-notify";
      # The node subscribes to watched machines with `ssh <host> mm agent`.
      # A user service's PATH has only systemd's bin, so without this every
      # subscription fails and the node stops watching (no bells from them).
      Environment = [
        "PATH=${pkgs.openssh}/bin:/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
      ];
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
