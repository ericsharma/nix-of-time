{ config, lib, ... }:

# wg-pangolin: the private network of the Pangolin cluster (10.100.0.0/24).
# trigkey serves PostgreSQL + Valkey on it; the nodes reach those and each
# other's Gerbil API (:3004). Plan: docs/plans/pangolin-cluster.md.
#
# Plain WireGuard, not Tailscale: public VPSs must not sit in the tailnet next
# to every device. trigkey is behind home NAT, so it dials out to both nodes
# and keeps the paths open; nothing opens at home.
#
# Imported by trigkey (it globs optional/) and explicitly by each node.
# A host finds itself in `members` by hostName. Private keys: sops
# "wg-pangolin/<host>" — secrets.yaml for trigkey, pangolin.yaml for the
# nodes (so a node can read the other node's key; they share SERVER_SECRET
# already, so that is no new trust).
let
  port = 51830; # 51820 is Gerbil's on the nodes
  members = {
    trigkey = {
      ip = "10.100.0.1";
      publicKey = "wpSaI1pnCOjZjs3PgrOlTW5QXgZKpU/6fpxXbHsy1FU=";
      endpoint = null;
    };
    racknerd-pangolin = {
      ip = "10.100.0.11";
      publicKey = "tJzLAgFUG1OkKE1UrRsSHxk3MNuDqAJcZ0R9d/KVQig=";
      endpoint = "172.245.86.223:${toString port}";
    };
    racknerd = {
      ip = "10.100.0.12";
      publicKey = "Xp2+r7wlTowDS46IOr4LW3prr46DYbMr0XuQw3XFeWM=";
      endpoint = "198.46.199.125:${toString port}";
    };
  };

  name = config.networking.hostName;
  self = members.${name};
  others = lib.filterAttrs (n: _: n != name) members;
in
{
  sops.secrets."wg-pangolin/${name}" = { };

  networking.wireguard.interfaces.wg-pangolin = {
    ips = [ "${self.ip}/24" ];
    privateKeyFile = config.sops.secrets."wg-pangolin/${name}".path;
    listenPort = lib.mkIf (self.endpoint != null) port;
    peers = lib.mapAttrsToList (
      _: peer:
      {
        inherit (peer) publicKey;
        allowedIPs = [ "${peer.ip}/32" ];
      }
      // lib.optionalAttrs (peer.endpoint != null) {
        inherit (peer) endpoint;
        # Only the side behind NAT needs to keep the path open.
        persistentKeepalive = if self.endpoint == null then 25 else null;
      }
    ) others;
  };

  networking.firewall.allowedUDPPorts = lib.mkIf (self.endpoint != null) [ port ];
}
