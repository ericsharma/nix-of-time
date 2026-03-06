{ config, ... }:

{
  services.newt = {
    enable = true;
    settings = {
      endpoint = "https://pangolin.ericsharma.xyz";
    };
    environmentFile = config.sops.secrets."newt/env".path;
  };
}
