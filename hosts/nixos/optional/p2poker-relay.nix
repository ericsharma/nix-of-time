{ pkgs, ... }:

let
  # nixpkgs has iroh-relay 1.3.0 (unstable); the p2poker clients use iroh 1.4,
  # so build the matching relay from the upstream tag. First build with a new
  # version: set cargoHash = lib.fakeHash, then copy the "got:" hash.
  iroh-relay = pkgs.rustPlatform.buildRustPackage rec {
    pname = "iroh-relay";
    version = "1.4.0";

    src = pkgs.fetchFromGitHub {
      owner = "n0-computer";
      repo = "iroh";
      rev = "v${version}";
      hash = "sha256-m2U3jtIsBWV2zp2myudCQ3PN/tDMWTlDfhEeELHRDPc=";
    };

    cargoHash = "sha256-hlf/DNoWrxWdPccDpIGP3LY+RphJJXX94EXGhCblRn4=";

    buildFeatures = [ "server" ];
    cargoBuildFlags = [
      "--bin"
      "iroh-relay"
    ];
    nativeBuildInputs = [ pkgs.lld ];
    # Tests need network access, which the build sandbox does not have.
    doCheck = false;
  };

  config = (pkgs.formats.toml { }).generate "iroh-relay.toml" {
    enable_relay = true;
    # Plain HTTP: Pangolin terminates TLS and forwards the WebSocket upgrade.
    http_bind_addr = "127.0.0.1:4227";
    # QUIC address discovery needs a local TLS cert and a forwarded UDP port.
    # Without it native peers on one LAN still connect directly; peers on
    # different networks stay on the relay.
    enable_quic_addr_discovery = false;
    enable_metrics = false;
    # The relay is public (no access control: game peers have new ids every
    # start). Bound what one client can push through it. A 6-player hand moves
    # about 0.3 MB in total, so these are far above honest use.
    limits = {
      accept_conn_limit = 10.0;
      accept_conn_burst = 50;
      client.rx = {
        bytes_per_second = 524288;
        max_burst_bytes = 4194304;
      };
    };
  };
in
{
  # ── p2poker iroh relay (plan 017 M4) ────────────────────────────────────────
  # Pangolin/Newt → 127.0.0.1:4227 (poker-relay.ericsharma.xyz).
  # Forwards end-to-end encrypted QUIC between p2poker peers (native apps, the
  # p2poker-peer CLI) that cannot reach each other directly. It cannot read
  # the traffic. Room discovery stays on the Hono relay in p2poker.nix.
  # NOT backed up — stateless (no data dir; config is in Nix).
  systemd.services.p2poker-relay = {
    description = "p2poker iroh relay";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${iroh-relay}/bin/iroh-relay --config-path ${config}";
      Restart = "on-failure";
      RestartSec = "5s";

      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };
}
