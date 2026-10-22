{ etd, ... }:

# etd: lets the E.T. iOS app reach this machine over iroh (no VPN, no open
# port), and joins it to the etd network: one member list for every machine
# and device, kept in sync between the machines (~/et-ios/docs/PLAN-network.md).
#
# Add a phone: `etd invite`, scan the QR code. Add a machine: `etd invite
# --machine` here, then `etd join <link>` there. Remove one: `etd revoke`.
# Check: `etd status`, `etd members`, `journalctl --user -u etd`.
#
# Data: ~/.config/etd (iroh key, network document, network key).
# NOT backed up — a lost key only means `etd join` / `etd invite` again.
{
  imports = [ etd.homeManagerModules.default ];

  services.etd.enable = true;
  # The manymux node runs from home/optional/manymux.nix (ssh-based) until
  # every machine is in the network (PLAN-network N6, second half). Two
  # nodes would fight over one socket.
  services.etd.manymux.enable = false;
}
