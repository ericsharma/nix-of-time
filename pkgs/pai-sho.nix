{
  lib,
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation rec {
  pname = "pai-sho";
  version = "0.2.2";

  src = fetchurl {
    url = "https://github.com/cablehead/pai-sho/releases/download/v${version}/pai-sho-v${version}-linux-amd64.tar.gz";
    hash = "sha256-1L87/VCw6c8H3REz4BlCPcgpaNvVohKidQbLE7fh/P0=";
  };

  installPhase = ''
    install -Dm755 pai-sho $out/bin/pai-sho
  '';

  meta = with lib; {
    description = "Multi-port tunnel daemon with automatic reconnection via iroh";
    homepage = "https://github.com/cablehead/pai-sho";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "pai-sho";
  };
}
