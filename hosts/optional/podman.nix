{ ... }:

{
  # ── Podman container runtime ─────────────────────────────────────────────────
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;          # provides `docker` CLI alias
    defaultNetwork.settings.dns_enabled = true;  # container DNS resolution
    autoPrune.enable = true;
  };

  # Use Podman as the OCI backend for virtualisation.oci-containers
  virtualisation.oci-containers.backend = "podman";

}
