{ config, pkgs, ... }:

let
  garage-webui = pkgs.stdenv.mkDerivation {
    pname   = "garage-webui";
    version = "1.1.0";

    src = pkgs.fetchurl {
      url    = "https://github.com/khairul169/garage-webui/releases/download/1.1.0/garage-webui-v1.1.0-linux-amd64";
      sha256 = "0ip74kw8zz3351035q80xkqc9dnkd554hg38y77gca3rjm35j2qq";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/garage-webui
      chmod +x $out/bin/garage-webui
    '';
  };
in

{
  # ── Secrets ───────────────────────────────────────────────────────────────────
  # garage-webui/env must contain:
  #   API_ADMIN_KEY=<same token as garage/admin-token>
  #   AUTH_USER_PASS=<user>:<bcrypt hash>   ← optional, enables basic auth
  #   Generate bcrypt hash with: htpasswd -bnBC 10 "" password | tr -d ':\n'
  sops.secrets."garage-webui/env" = {};

  # ── System user ───────────────────────────────────────────────────────────────
  users.users.garage-webui = {
    isSystemUser = true;
    group        = "garage-webui";
  };
  users.groups.garage-webui = {};

  # ── Service ───────────────────────────────────────────────────────────────────
  systemd.services.garage-webui = {
    description = "Garage Web UI";
    after       = [ "garage.service" ];
    wantedBy    = [ "multi-user.target" ];

    environment = {
      API_BASE_URL   = "http://127.0.0.1:3903";
      S3_ENDPOINT_URL = "http://127.0.0.1:3900";
      S3_REGION      = "garage";
      PORT           = "3909";
    };

    serviceConfig = {
      ExecStart       = "${garage-webui}/bin/garage-webui";
      EnvironmentFile = config.sops.secrets."garage-webui/env".path;
      User            = "garage-webui";
      Group           = "garage-webui";
      Restart         = "on-failure";
    };
  };
}
