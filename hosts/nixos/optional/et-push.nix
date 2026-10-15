{ ... }:

{
  # ── E.T. push notifications ──────────────────────────────────────────────────
  # APNs key for the E.T. iOS tmux client. home/trigkey/et-notify.nix sends a
  # push from tmux's alert-bell hook, as eric, so eric must be able to read it.
  # The key lives in its own sops file (see .sops.yaml).
  sops.secrets.et-apns-key = {
    sopsFile = ../../../secrets/et.yaml;
    key = "apns-key";
    owner = "eric";
    mode = "0400";
  };
}
