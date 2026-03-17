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
    VENV="/var/lib/tapmap/venv"
    if [ ! -f "$VENV/bin/python" ]; then
      ${pkgs.python3}/bin/python -m venv "$VENV"
      "$VENV/bin/pip" install --no-cache-dir -r ${tapmap-src}/requirements.txt
    fi
  '';
in
{
  # ── TapMap (network connection visualizer) ──────────────────────────────────
  # Port: 8050
  # GeoLite2 databases: /var/lib/tapmap/TapMap/GeoLite2-{City,ASN}.mmdb

  systemd.services.tapmap = {
    description = "TapMap network connection visualizer";
    after    = [ "network-online.target" ];
    wants    = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type             = "simple";
      WorkingDirectory = tapmap-src;
      ExecStartPre     = tapmap-setup;
      ExecStart        = "/var/lib/tapmap/venv/bin/python tapmap.py";
      Restart          = "on-failure";
      RestartSec       = 10;

      # Least-privilege: psutil.net_connections() needs CAP_NET_ADMIN + CAP_NET_RAW
      DynamicUser         = true;
      StateDirectory      = "tapmap";
      AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
    };

    environment = {
      XDG_DATA_HOME = "/var/lib/tapmap";
      TAPMAP_PORT   = "8050";
    };
  };

  # StateDirectory creates /var/lib/tapmap owned by the DynamicUser.
  # After first rebuild, place GeoLite2 databases:
  #   sudo cp GeoLite2-{City,ASN}.mmdb /var/lib/private/tapmap/TapMap/
}
