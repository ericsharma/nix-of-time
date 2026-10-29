{
  lib,
  stdenv,
  fetchurl,
}:

stdenv.mkDerivation rec {
  pname = "grok-build";
  version = "1.0.70";

  src = fetchurl {
    url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${version}-linux-x86_64";
    hash = "sha256-ItKBxZZMVEQUcygJa6KiIfPwh0xoWOJ8glZWqA9uWOk=";
  };

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/grok
    ln -s $out/bin/grok $out/bin/agent
  '';

  meta = with lib; {
    description = "xAI Grok CLI (coding assistant)";
    homepage = "https://x.ai/cli";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "grok";
  };
}
