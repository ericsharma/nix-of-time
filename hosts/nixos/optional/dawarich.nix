{ ... }:

{
  # LAN proxy to the Dawarich stack in the LXC. LAN only; public access is
  # d.ericsharma.xyz through Pangolin.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport 3030 accept comment "dawarich lan proxy from LAN"
  '';

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
