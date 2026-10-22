{
  config,
  pkgs,
  etd,
  ...
}:

# etd on the m1-mini: lets E.T. reach this machine over iroh, as a member of
# trigkey's etd network (~/et-ios/docs/PLAN-network.md). nix-darwin has no
# Home Manager here, so this is the launchd half of etd's Home Manager module.
#
# Joined once by hand, under the name the other machines use for it:
#   etd join <link from `etd invite --machine` on trigkey> --name mac-mini
# (the host name is m1-mini; manymux, `ws` and the app call it mac-mini).
#
# The manymux node runs from ./manymux.nix (ssh-based) until every machine is
# in the network (PLAN-network N6, second half).
#
# Data: ~/Library/Application Support/etd (iroh key, network document, network
# key). NOT backed up — a lost key only means `etd join` again.
let
  package = etd.packages.${pkgs.stdenv.hostPlatform.system}.etd;
  home = config.users.users.${config.system.primaryUser}.home;
in
{
  # etd-ssh too; and on PATH for a non-interactive ssh.
  environment.systemPackages = [ package ];
  # `mm ls` / `mm attach` in a shell here reach the other machines through
  # etd. The node's own launchd agent (./manymux.nix) is left as it is: a
  # changed agent is reloaded, and that would end every session here.
  environment.variables.MM_SSH = "${package}/bin/etd-ssh";

  launchd.user.agents.etd.serviceConfig = {
    ProgramArguments = [ "${package}/bin/etd" ];
    # Keep manymux's hosts.toml equal to the network's machines.
    EnvironmentVariables.ETD_MANYMUX_HOSTS = "1";
    RunAtLoad = true;
    KeepAlive = true;
    StandardOutPath = "${home}/Library/Logs/etd.log";
    StandardErrorPath = "${home}/Library/Logs/etd.log";
  };
}
