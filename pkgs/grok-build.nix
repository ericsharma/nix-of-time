{ lib, stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "grok-build";
  version = "0.2.11";

  src = fetchurl {
    url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${version}-linux-x86_64";
    hash = "sha256-KyVDM8z4Sd0aT9J+mQqUHSjgx+maSluqkEFg9eS6bHY=";
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
