{ ... }:

# manymux client settings. The node itself (`mm daemon`), `mm`, and
# MM_SSH=etd-ssh come from etd's module (../optional/etd.nix,
# services.etd.manymux): every machine of the etd network reaches the others
# through etd, with no ssh keys or `mm add` (~/et-ios/docs/PLAN-network.md).
#
# Data: ~/.config/manymux (etd keeps hosts.toml equal to the network's
# machines). Sessions live in memory; trigkey checkpoints them
# (../trigkey/manymux-checkpoint.nix).
{
  # The key for manymux's control mode (`mm attach`). Its default, Ctrl-],
  # does not reach trigkey from the laptop's terminal; Ctrl-b (the tmux
  # prefix) does. Pressed twice quickly, it sends one Ctrl-b to the session.
  home.sessionVariables.MM_PREFIX = "C-b";
}
