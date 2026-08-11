{ config, ericsharma-xyz, ... }:

{
  # ── ericsharma.xyz (personal website, static HTML) ──────────────────────────
  # Port: 4208 (localhost only, fronted by Pangolin/Newt → ericsharma.xyz)
  #
  # No build step: the flake input is a directory containing index.html at its
  # root, so nginx serves the /nix/store path directly. Bump with
  # `nix flake update ericsharma-xyz`.
  #
  # The source repo is private, so nix needs a GitHub token to fetch it at
  # rebuild time. `nix.extraOptions` !include's a sops-decrypted file
  # (`access-tokens = github.com=…`) into the system nix.conf, so subsequent
  # rebuilds on the host pick up the token automatically. First-time bootstrap
  # (before /run/secrets/nix/github-token exists) needs a one-shot env var:
  #   sudo NIX_CONFIG="access-tokens = github.com=$(gh auth token)" \
  #     nixos-rebuild switch --flake .#trigkey
  sops.secrets."nix/github-token" = { };
  nix.extraOptions = ''
    !include ${config.sops.secrets."nix/github-token".path}
  '';

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."ericsharma.xyz" = {
      listen = [
        {
          addr = "127.0.0.1";
          port = 4208;
        }
      ];
      root = "${ericsharma-xyz}";
      locations."/" = {
        tryFiles = "$uri $uri/ =404";
      };
    };
  };
}
