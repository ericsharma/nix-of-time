{
  lib,
  stdenv,
  fetchurl,
}:

let
  # x.ai's platform names (https://x.ai/cli/install.sh) and each binary's hash.
  sources = {
    x86_64-linux = {
      platform = "linux-x86_64";
      hash = "sha256-ItKBxZZMVEQUcygJa6KiIfPwh0xoWOJ8glZWqA9uWOk=";
    };
    aarch64-darwin = {
      platform = "macos-aarch64";
      hash = "sha256-XIpoglG/YeNTcLgotqNTsKIPzD9kAA3oqR1CYDnynOw=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "grok-build: no binary for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation rec {
  pname = "grok-build";
  version = "1.0.70";

  src = fetchurl {
    url = "https://storage.googleapis.com/grok-build-public-artifacts/cli/grok-${version}-${source.platform}";
    inherit (source) hash;
  };

  dontUnpack = true;
  # A changed byte breaks the macOS code signature.
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    install -Dm755 $src $out/bin/grok
    ln -s $out/bin/grok $out/bin/agent
  '';

  meta = with lib; {
    description = "xAI Grok CLI (coding assistant)";
    homepage = "https://x.ai/cli";
    license = licenses.unfree;
    platforms = builtins.attrNames sources;
    mainProgram = "grok";
  };
}
