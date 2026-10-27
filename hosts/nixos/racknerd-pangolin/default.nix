{ ... }:

# Pangolin node 1 (172.245.86.223): every public DNS record points here.
{
  imports = [
    ./hardware-configuration.nix
    ../pangolin-node
    ../optional/podman.nix # oci-containers backend for the Pangolin stack
    ../pangolin-node/pangolin.nix # Pangolin + Gerbil + Traefik on :80, :443, :51820/udp
  ];

  networking.hostName = "racknerd-pangolin";
}
