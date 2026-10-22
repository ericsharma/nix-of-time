{ ... }:

# etd on trigkey: the first machine of the etd network (it made the network
# key), and the one that sends pushes: et-notify.nix sets ETD_NOTIFY_COMMAND.
# The module itself: ../optional/etd.nix.
{
  imports = [ ../optional/etd.nix ];
}
