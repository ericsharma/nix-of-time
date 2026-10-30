{ polygon-dynamics, ... }:

{
  # ── Polygon Dynamics (outer billiards WebGL renderer, static) ────────────────
  # Port: 4211 (localhost only, fronted by Pangolin/Newt → polygons.ericsharma.xyz)
  # State: none. NOT backed up — the site is the flake input, nothing else.
  #
  # No build step: the repo root holds index.html, main.js and style.css, so
  # nginx serves the /nix/store path directly. Bump with
  # `nix flake update polygon-dynamics`. The repo is private; the GitHub token
  # wiring for the fetch lives in ericsharma-xyz.nix.
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."polygons.ericsharma.xyz" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 4211;
        }
      ];
      root = "${polygon-dynamics}";
      locations."/" = {
        tryFiles = "$uri $uri/ =404";
      };
    };
  };
}
