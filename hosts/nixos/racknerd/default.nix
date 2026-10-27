{ ... }:

# Pangolin node 2 (198.46.199.125). Spare until the cluster: the stack is not
# imported here, so only one Pangolin (SQLite, Community Edition) runs at a
# time. /var/lib/pangolin holds a copy of node 1's data from 2026-10-27.
{
  imports = [
    ./hardware-configuration.nix
    ../pangolin-node
  ];

  networking.hostName = "racknerd";
}
