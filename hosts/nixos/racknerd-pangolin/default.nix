{ ... }:

# Pangolin node 1 (172.245.86.223): every public DNS record points here.
# A cluster node since 2026-10-27; the CE data it ran on until then is kept
# in /var/lib/pangolin (rollback: import ../pangolin-node/pangolin.nix again).
{
  imports = [
    ./hardware-configuration.nix
    ../pangolin-node
    ../optional/podman.nix # oci-containers backend
    ../pangolin-node/cluster.nix # Pangolin EE + Gerbil + Traefik, state on trigkey
  ];

  networking.hostName = "racknerd-pangolin";
}
