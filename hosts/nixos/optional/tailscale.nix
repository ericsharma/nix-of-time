{ config, ... }:

{
  # ── Tailscale (mesh VPN for remote access) ───────────────────────────────────
  # Auth is fully declarative via authKeyFile — no manual `tailscale up` needed.
  # Generate the auth key in the Tailscale admin console (reusable: off, ephemeral: off,
  # tags: off) and store it in sops as tailscale.authkey.
  #
  # No --ssh: Tailscale SSH logs in by tailnet identity and skips the managed
  # authorized_keys, and eric has passwordless sudo here. Tailnet SSH goes
  # through OpenSSH (trigkey/default.nix admits port 22 on tailscale0).
  # --accept-dns=false  keeps host DNS as-is; MagicDNS still resolves for clients

  sops.secrets."tailscale/authkey" = { };

  services.tailscale = {
    enable = true;
    openFirewall = true; # allows UDP 41641 for direct (non-relay) connections
    authKeyFile = config.sops.secrets."tailscale/authkey".path;
    extraUpFlags = [
      "--accept-dns=false"
    ];
  };
}
