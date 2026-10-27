{ ... }:

# Pangolin node 2 (198.46.199.125). Runs the Enterprise cluster node (phase A
# of docs/plans/pangolin-cluster.md) while node 1 keeps the CE stack and all
# public DNS. /var/lib/pangolin holds a copy of node 1's CE data from
# 2026-10-27; the cluster uses /var/lib/pangolin-cluster.
{
  imports = [
    ./hardware-configuration.nix
    ../pangolin-node
    ../optional/podman.nix # oci-containers backend
    ../pangolin-node/cluster.nix # Pangolin EE + Gerbil + Traefik, state on trigkey
  ];

  networking.hostName = "racknerd";
}
