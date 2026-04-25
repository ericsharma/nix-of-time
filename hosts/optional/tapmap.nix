{ pkgs, ... }:

let
  tapmap-src = pkgs.fetchFromGitHub {
    owner = "olalie";
    repo  = "tapmap";
    rev   = "d2fe2712a0f08dddb7ba11534a4fba64797da872";
    hash  = "sha256-ZLZEzR1e1rAouUd/LPIPEGLYYUIEeav9CmDubwL0Tgc=";
  };

  # Create venv and pip install on first start (nixpkgs dash/plotly are too old)
  tapmap-setup = pkgs.writeShellScript "tapmap-setup" ''
    set -euo pipefail
    VENV="/srv/tapmap/venv"
    if [ ! -f "$VENV/pyvenv.cfg" ]; then
      ${pkgs.python3}/bin/python -m venv "$VENV"
      "$VENV/bin/python" -m pip install --no-cache-dir -r ${tapmap-src}/requirements.txt
    fi
  '';
in
{
  # ── TapMap (network connection visualizer) ──────────────────────────────────
  # Port: 8050
  # GeoLite2 databases: /srv/tapmap/TapMap/GeoLite2-{City,ASN}.mmdb

  systemd.services.tapmap = {
    description = "TapMap network connection visualizer";
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type             = "simple";
      WorkingDirectory = tapmap-src;
      ExecStartPre     = tapmap-setup;
      ExecStart        = "/srv/tapmap/venv/bin/python tapmap.py";
      Restart          = "on-failure";
      RestartSec       = 10;

      # psutil.net_connections() needs CAP_NET_ADMIN + CAP_NET_RAW to see all connections
      User                = "eric";
      Group               = "users";
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
    };

    environment = {
      XDG_DATA_HOME = "/srv/tapmap";
      TAPMAP_PORT   = "8050";
    };
  };

  systemd.tmpfiles.rules = [
    "d /srv/tapmap        0755 root root -"
    "d /srv/tapmap/TapMap 0755 root root -"
  ];
}
