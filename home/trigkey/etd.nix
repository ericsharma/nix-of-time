{ etd, ... }:

# etd: lets the E.T. iOS app reach tmux on trigkey over iroh, without
# Tailscale. A user service (it must reach the tmux socket in /run/user/1000).
# The phone finds trigkey by its iroh key; connections are direct, or through
# the n0 relay when hole punching fails. No open port.
#
# Add a phone: `etd pair`, then scan the QR code. Remove one: `etd revoke`.
# Check: `etd status`, `journalctl --user -u etd`.
# Source and plan: github.com/ericsharma/etd, ~/et-ios/docs/PLAN-iroh.md.
#
# Data: ~/.config/etd (iroh key, paired devices), ~/.local/state/etd.
# NOT backed up — a lost key only means `etd pair` again on each phone.
{
  imports = [ etd.homeManagerModules.default ];

  services.etd.enable = true;
  # The manymux node runs from home/optional/manymux.nix (ssh-based) until
  # this machine's network holds gmktec and the m1-mini (PLAN-network N6).
  # Two nodes would fight over one socket.
  services.etd.manymux.enable = false;
}
