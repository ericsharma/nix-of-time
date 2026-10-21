{
  config,
  pkgs,
  p2poker-native,
  ...
}:

let
  # The always-on dealer from crates/p2poker-sequencer (path deps on the other
  # crates, so the whole repo is the source). New lockfile: set
  # cargoHash = lib.fakeHash, build, copy the "got:" hash.
  p2poker-sequencer = pkgs.rustPlatform.buildRustPackage {
    pname = "p2poker-sequencer";
    version = "0-${p2poker-native.shortRev or "dirty"}";
    src = p2poker-native;
    cargoRoot = "crates/p2poker-sequencer";
    buildAndTestSubdir = "crates/p2poker-sequencer";
    cargoHash = "sha256-HnsvICwleLITqC+7RiIEo8m5x8tDE8qmFSU3hWP3avI=";
    # Tests start a relay and peers on the network, which the sandbox lacks.
    doCheck = false;
  };
in
{
  # ── p2poker dealer (plan 017 M6) ────────────────────────────────────────────
  # Pangolin/Newt → 127.0.0.1:4237 (poker-dealer.ericsharma.xyz).
  # POST /tables opens a table and deals it without a seat, a key or cards
  # (every player still verifies every step); GET /health. Talks to the
  # p2poker-relay (iroh) and the room directory in p2poker.nix.
  # NOT backed up — state is the dealer's identity key (a new key works for
  # new tables) and the open tables (live games, useless after 12 h).
  # APNs token key (sops p2poker/apns_key) sends "your turn" pushes to away
  # players; the device tokens live in memory only.
  sops.secrets."p2poker/apns_key" = { };

  systemd.services.p2poker-sequencer = {
    description = "p2poker dealer";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "p2poker-relay.service"
    ];
    wants = [ "network-online.target" ];

    environment = {
      P2POKER_SEQ_LISTEN = "127.0.0.1:4237";
      P2POKER_RELAY = "https://poker-relay.ericsharma.xyz";
      P2POKER_DIRECTORY = "wss://poker.ericsharma.xyz/relay";
      P2POKER_SEQ_IDENTITY = "/var/lib/p2poker-sequencer/dealer.key";
      # Open tables, saved after every change and restored at start.
      P2POKER_SEQ_TABLES = "/var/lib/p2poker-sequencer/tables";
      P2POKER_APNS_KEY = "%d/apns.p8";
      P2POKER_APNS_KEY_ID = "7K8NMK5U73";
      RUST_LOG = "info";
    };

    serviceConfig = {
      ExecStart = "${p2poker-sequencer}/bin/p2poker-sequencer";
      LoadCredential = "apns.p8:${config.sops.secrets."p2poker/apns_key".path}";
      Restart = "on-failure";
      RestartSec = "5s";
      # On stop the dealer leaves each table cleanly so players wait for it.
      TimeoutStopSec = "15s";
      StateDirectory = "p2poker-sequencer";
      StateDirectoryMode = "0700";

      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
    };
  };
}
