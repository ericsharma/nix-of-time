{ ... }:

let
  checkout = "/home/eric/iroh-cam";
  port = 4230;
  # The camera's endpoint id. iroh finds the address through n0's pkarr DNS,
  # so a new DHCP lease on the camera changes nothing. Not a secret: the
  # camera admits only its members. The id lives in the camera's NVS since
  # firmware 0.2.0 and survives reflashing (scripts/fw.sh skips NVS); it
  # changes only after `fw.sh erase-state`.
  ticket = "927317be6a448f6b6127e9925e6eee3f1f5802032067e6725e227fac929b2205";
in
{
  # ── iroh-cam viewer (ESP32-CAM over iroh) ────────────────────────────────────
  # Dials the ESP32-CAM (on Wi-Fi, flashed from gmktec) over iroh and serves
  # its stream as MJPEG. See docs/services/iroh-cam.md.
  # Source: ~/iroh-cam (no GitHub remote yet).
  # Port:   4230 (127.0.0.1). LAN name `cam.local` through portless (see
  #         inventory.nix). No auth on the LAN side: anyone on the LAN can
  #         watch. Keep it off Pangolin.
  # Data:   ~/.config/iroh-cam/viewer.key, the viewer's iroh key. It is the
  #         camera's first owner (claimed 2026-11-04). NOT backed up: with it
  #         lost, another owner re-invites this host (`iroh-cam-viewer ctl
  #         <id> invite viewer`, then `iroh-cam-viewer pair <ticket>`).
  #
  # Runs the binary from the checkout as eric, like nam-shub, because the
  # project changes daily. After a change: `cargo build --release` in the
  # ~/iroh-cam workspace, then `sudo systemctl restart iroh-cam`. The binary
  # links the glibc of the nixpkgs it was built with, so rebuild it after a
  # nixpkgs bump.
  systemd.services.iroh-cam = {
    description = "iroh-cam viewer (port ${toString port})";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      User = "eric";
      Group = "users";
      ExecStart = "${checkout}/target/release/iroh-cam-viewer watch ${ticket} --http 127.0.0.1:${toString port}";
      # The viewer redials the camera by itself; this covers a crash.
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      # Reads the key from ~/.config/iroh-cam and the binary from ~/iroh-cam.
      ProtectHome = "read-only";
    };
  };
}
