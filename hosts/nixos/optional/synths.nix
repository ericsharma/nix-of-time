{ pkgs, synths, ... }:

{
  # ── Synth hub (browser synth engines, static) ──────────────────────────────
  # Port: 4241 (localhost only, fronted by Pangolin/Newt → synths.ericsharma.xyz)
  # State: none. NOT backed up — the site is built from the flake input.
  #
  # ericsharma/synths builds each engine (FM-1 firmwares: DUB-1, NACHTFAHRT ...)
  # from source and assembles one static site: /<id>/, /_embed/, /engines.json.
  # Engines keep their settings in the viewer's browser. EternaTV embeds them as
  # audio sources (radio-video.nix). Add an engine in the synths repo, then
  # `nix flake update synths`.
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."synths.ericsharma.xyz" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 4241;
        }
      ];
      root = "${synths.packages.${pkgs.system}.site}";
      # Store files all have mtime 1970, so ETag and Last-Modified do not change
      # between builds. A short max-age instead; an engine is about 500 KB.
      extraConfig = ''
        etag off;
        if_modified_since off;
      '';
      locations."/" = {
        tryFiles = "$uri $uri/ =404";
        extraConfig = ''
          add_header Cache-Control "public, max-age=300" always;
        '';
      };
      # The catalog, for host apps on other origins.
      locations."= /engines.json".extraConfig = ''
        add_header Cache-Control "public, max-age=300" always;
        add_header Access-Control-Allow-Origin * always;
      '';
    };
  };
}
