{ config, ... }:

{
  # ── Tailscale (mesh VPN for remote access) ───────────────────────────────────
  # Auth is fully declarative via authKeyFile — no manual `tailscale up` needed.
  # Generate the auth key in the Tailscale admin console (reusable: off, ephemeral: off,
  # tags: off) and store it in sops as tailscale.authkey.
  #
  # --ssh           lets `ssh eric@trigkey` work via Tailscale identity (no key prompt)
  # --accept-dns=false  keeps host DNS as-is; MagicDNS still resolves for clients

  sops.secrets."tailscale/authkey" = {};

  services.tailscale = {
    enable        = true;
    openFirewall  = true;  # allows UDP 41641 for direct (non-relay) connections
    authKeyFile   = config.sops.secrets."tailscale/authkey".path;
    extraUpFlags  = [ "--ssh" "--accept-dns=false" ];
  };
}
