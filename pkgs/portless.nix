{
  lib,
  stdenv,
  fetchFromGitHub,
  nodejs_24,
  pnpm_9,
  makeWrapper,
}:

# Portless is not in nixpkgs (as of 2026-08). Upstream is a pnpm workspace
# monorepo with the publishable package at packages/portless. We fetch the git
# source pinned by tag, build with pnpm, and expose the CLI as `portless`.
#
# Why 0.13.0 and not the newest tag: from v0.13.1 upstream sets
# `packageManager: pnpm@11` and `engines.node >=24`. nixpkgs 25.11 carries pnpm
# 10 at the newest, and `pnpm.fetchDeps` refuses the engines field, so the
# dependency fetch fails before it starts. 0.13.0 is the last tag on pnpm 9,
# and it already has everything this module uses: `proxy start --lan`,
# `alias`, `list --json`, and `--no-tls`. Revisit when nixpkgs ships pnpm 11.
#
# Version bumps: change `version`, set both hashes back to `lib.fakeHash`, then
# run
#   nix build --no-link .#nixosConfigurations.gmktec.pkgs.portless
# twice. The first failure prints the real value for `src.hash`; substitute it
# and rerun. The second prints the real value for `pnpmDeps.hash`; substitute
# it and rerun. The third run builds cleanly.
#
# LAN mode requires avahi at runtime (portless shells out to
# avahi-publish-address). That is a service-side concern, not a package one, so
# it is handled in the NixOS module, not here.

let
  version = "0.13.0";
in

stdenv.mkDerivation (finalAttrs: {
  pname = "portless";
  inherit version;

  src = fetchFromGitHub {
    owner = "vercel-labs";
    repo = "portless";
    rev = "v${version}";
    hash = "sha256-ZuhYcT7nvZXlEIQkxEklqK2DgTuW8yIf8m4cMxChMI4=";
  };

  pnpmDeps = pnpm_9.fetchDeps {
    inherit (finalAttrs) pname version src;
    # nixpkgs 25.11 refuses to guess this. 2 is the current fetcher.
    fetcherVersion = 2;
    hash = "sha256-83ycx9P3GUdAhvQvPeeFpHQkXZKO08kFTI4YYgk0L88=";
  };

  nativeBuildInputs = [
    nodejs_24
    pnpm_9.configHook
    makeWrapper
  ];

  # Build only the publishable package. Turbo would rebuild the whole monorepo,
  # which is fine but slow — the workspace filter is cheaper and produces the
  # same dist/.
  buildPhase = ''
    runHook preBuild
    pnpm --filter portless build
    runHook postBuild
  '';

  # `pnpm deploy` is not used, and is not needed.
  #
  # It cannot work: even with `--prod` it re-resolves the direct
  # devDependencies against the registry, which the build sandbox cannot reach.
  # `--offline` only moves the failure to ERR_PNPM_NO_OFFLINE_META, because
  # pnpmDeps carries the packages but not the registry metadata.
  #
  # It is not needed because `packages/portless` declares **no** runtime
  # dependencies: tsup bundles the CLI into `dist/`. The output is that
  # directory, its manifest, and a wrapper. No node_modules ship at all, which
  # is also why this derivation is a few hundred kB and not the 1.3 GB that
  # copying the built workspace produced.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/portless
    cp -a packages/portless/dist packages/portless/package.json $out/lib/portless/

    # The manifest declares one or more bin entries. Read them rather than
    # hard-code a path — the upstream layout is pre-1.0 and has moved between
    # releases.
    node -e '
      const fs = require("fs");
      const pkg = JSON.parse(fs.readFileSync(process.env.out + "/lib/portless/package.json"));
      const bins = typeof pkg.bin === "string" ? { [pkg.name.split("/").pop()]: pkg.bin } : pkg.bin;
      for (const [name, rel] of Object.entries(bins)) {
        console.log(name + " " + rel);
      }
    ' | while read name rel; do
      target="$out/lib/portless/$rel"
      test -f "$target" || { echo "portless bin $name -> $rel not found in the staged tree" >&2; exit 1; }
      chmod +x "$target"
      makeWrapper ${nodejs_24}/bin/node "$out/bin/$name" \
        --add-flags "$target"
    done

    runHook postInstall
  '';

  # Sanity check that the wrapped CLI actually starts. `portless --version`
  # exits 0 and prints the version string without touching the network or the
  # state dir.
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/portless --version | grep -q "${version}"
  '';

  meta = {
    description = "Stable, named local URLs for local services";
    homepage = "https://portless.sh";
    downloadPage = "https://github.com/vercel-labs/portless/releases";
    license = lib.licenses.asl20;
    mainProgram = "portless";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
