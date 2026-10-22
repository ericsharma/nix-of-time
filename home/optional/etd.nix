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
  # The manymux node runs from etd's module (on by default): MM_SSH=etd-ssh
  # for the node and for shells, and etd keeps manymux's hosts.toml equal to
  # the network's machines. The node unit is never restarted by a deploy (a
  # restart ends every session); a change applies at its next start.
  services.etd.manymux.enable = true;
}
