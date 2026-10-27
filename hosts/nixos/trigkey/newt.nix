{ config, pkgs, ... }:

{
  sops.secrets."newt/env" = { };

  services.newt = {
    enable = true;
    # 25.11 ships 1.5.2, which the Pangolin EE cluster never registers a
    # tunnel for (websocket connects, then nothing). Unstable is current.
    package = pkgs.unstable.fosrl-newt;
    settings = {
      endpoint = "https://pangolin.ericsharma.xyz";
    };
    environmentFile = config.sops.secrets."newt/env".path;
  };
}
