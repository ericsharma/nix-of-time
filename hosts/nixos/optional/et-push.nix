{ ... }:

{
  # ── E.T. push notifications ──────────────────────────────────────────────────
  # APNs key for the E.T. iOS app. home/trigkey/et-notify.nix sends a
  # push (run by etd for a manymux bell) as eric, so eric must be able to read it.
  # The key lives in its own sops file (see .sops.yaml).
  sops.secrets.et-apns-key = {
    sopsFile = ../../../secrets/et.yaml;
    key = "apns-key";
    owner = "eric";
    mode = "0400";
  };
}
