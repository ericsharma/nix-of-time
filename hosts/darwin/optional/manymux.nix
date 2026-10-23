{ config, pkgs, ... }:

# manymux node (`mm daemon`) for the primary user: it owns this machine's
# terminal sessions. trigkey reaches it with `ssh <host> mm agent`; the E.T.
# app reaches it through etd on trigkey. Plan: ~/et-ios/docs/PLAN-manymux.md.
#
# environment.systemPackages, not home.packages: a non-interactive ssh here
# has /run/current-system/sw/bin in PATH but not the per-user profile.
#
# A darwin-rebuild that changes the agent (a manymux bump) reloads it, and a
# node restart ends every session. Before a bump, run `mm checkpoint save`.
#
# NOT backed up — sessions live in memory; the config is empty on this host.
let
  user = config.system.primaryUser;
  home = config.users.users.${user}.home;
  # Claude Code here is the self-updating install in ~/.claude/local, which
  # the shell only knows as an alias. The node runs a session's command
  # without a shell, so `mm new claude` (and E.T.'s New session > Claude)
  # needs a real `claude` on PATH.
  claude = pkgs.writeShellScriptBin "claude" ''
    exec ${home}/.claude/local/claude "$@"
  '';
in
{
  environment.systemPackages = [
    pkgs.manymux
    claude
  ];

  launchd.user.agents.manymux.serviceConfig = {
    # --no-notify: headless; bells reach the phone through etd on trigkey.
    ProgramArguments = [
      "${pkgs.manymux}/bin/mm"
      "daemon"
      "--no-notify"
    ];
    # launchd's default PATH is only /usr/bin:/bin:/usr/sbin:/sbin; sessions
    # started with a command (not a login shell) find programs through this.
    EnvironmentVariables.PATH = builtins.concatStringsSep ":" [
      "${home}/.nix-profile/bin"
      "/run/current-system/sw/bin"
      "/nix/var/nix/profiles/default/bin"
      "/opt/homebrew/bin"
      "/usr/local/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
    RunAtLoad = true;
    KeepAlive = true;
    StandardErrorPath = "${home}/Library/Logs/manymux-daemon.log";
  };
}
