{ ... }:

{
  networking.firewall.allowedTCPPorts = [ 3030 ];

  services.nginx = {
    enable = true;
    virtualHosts."dawarich-lan" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 3030;
        }
      ];
      locations."/" = {
        proxyPass = "http://10.0.100.10:3000";
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };
    };
  };
}
