{ ... }:

# Lean on purpose: 1 GB RAM, 20 GB disk. Only etd (+ its manymux node), so
# the E.T. app and `etd-ssh racknerd` reach this box.
{
  imports = [ ../optional/etd.nix ];

  home.username = "eric";
  home.homeDirectory = "/home/eric";
  home.stateVersion = "25.11";
}
