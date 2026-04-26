{ pkgs, belle-watson-studios, ... }:

let
  # Static Vite SPA built at Nix eval time. No runtime server, no secrets —
  # nginx serves the dist/ directory directly from the Nix store.
  #
  # First build will fail with a hash mismatch. Copy the "got:" hash printed
  # by Nix into pnpmDeps.hash below and rebuild.
  site = pkgs.stdenv.mkDerivation (finalAttrs: {
    pname   = "belle-watson-studios";
    version = "0.0.0";
    src     = belle-watson-studios;

    nativeBuildInputs = [
      pkgs.nodejs_22
      pkgs.pnpm_9
      pkgs.pnpm_9.configHook
    ];

    pnpmDeps = pkgs.pnpm_9.fetchDeps {
      inherit (finalAttrs) pname version src;
      fetcherVersion = 2;
      hash = "sha256-UPfT6vAR4cOuf4Vtqwe9IKM+Bs2AJI8uHFjurvFn6Pk=";
    };

    buildPhase = ''
      runHook preBuild
      pnpm run build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  });
in
{
  # ── Belle Watson Studios (static marketing site) ────────────────────────────
  # Port: 4204 (localhost only, fronted by Pangolin/Newt → bellewatsonstudio.com)

  services.nginx = {
    enable                  = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."bellewatsonstudio.com" = {
      listen = [ { addr = "127.0.0.1"; port = 4204; } ];
      root   = "${site}";
      locations."/" = {
        tryFiles = "$uri $uri/ /index.html";
      };
    };
  };
}
