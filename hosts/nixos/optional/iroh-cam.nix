{ ... }:

let
  checkout = "/home/eric/iroh-cam";
  port = 4230;
  # The camera's short ticket: its endpoint id only. iroh finds the address
  # through n0's pkarr DNS, so a new DHCP lease on the camera changes nothing.
  # Not a secret: the camera admits only the endpoint ids in its build-time
  # ALLOWED_VIEWERS list. It changes only when the firmware's IROH_SECRET does
  # (a `cargo clean` of the firmware without IROH_SECRET set).
  ticket = "endpointadz7pqdx5r24xvqdhslfsnkx5t654ihyfpyoihocknoizdl5pcewqaa";
in
{
  # ── iroh-cam viewer (ESP32-CAM over iroh) ────────────────────────────────────
  # Dials the ESP32-CAM (on Wi-Fi, flashed from gmktec) over iroh and serves
  # its stream as MJPEG. See docs/services/iroh-cam.md.
  # Source: ~/iroh-cam (no GitHub remote yet).
  # Port:   4230 (127.0.0.1). LAN name `cam.local` through portless (see
  #         inventory.nix). No auth on the LAN side: anyone on the LAN can
  #         watch. Keep it off Pangolin.
  # Data:   ~/.config/iroh-cam/viewer.key, the viewer's iroh key. Its endpoint
  #         id is in the firmware's ALLOWED_VIEWERS; a new key means a reflash.
  #         NOT backed up: losing it costs one reflash.
  #
  # Runs the binary from the checkout as eric, like nam-shub, because the
  # project changes daily. After a change: `cargo build --release` in
  # ~/iroh-cam/viewer, then `sudo systemctl restart iroh-cam`. The binary
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
      ExecStart = "${checkout}/viewer/target/release/iroh-cam-viewer watch ${ticket} --http 127.0.0.1:${toString port}";
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
