{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
}:

# Google's Antigravity CLI (`agy`). The musl build is statically linked, so it
# runs on NixOS with no patching. Its own updater cannot replace a store path:
# it is turned off, and a version bump goes through this file.
stdenv.mkDerivation rec {
  pname = "antigravity-cli";
  version = "1.4.10";

  src = fetchurl {
    url = "https://github.com/google-antigravity/antigravity-cli/releases/download/${version}/agy_cli_linux_x64_musl.tar.gz";
    hash = "sha256-BRyJuRbZwV4xNZtOjM2JqFD8zp4/Ohng/isbZebpkf4=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [ makeWrapper ];
  dontStrip = true;

  installPhase = ''
    install -Dm755 antigravity $out/libexec/agy
    makeWrapper $out/libexec/agy $out/bin/agy \
      --argv0 agy \
      --set-default AGY_CLI_DISABLE_AUTO_UPDATE true
  '';

  meta = with lib; {
    description = "Google Antigravity CLI (terminal coding agent)";
    homepage = "https://github.com/google-antigravity/antigravity-cli";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "agy";
  };
}
