{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  ffmpeg,
  opencv,
  glib,
  clang,
  llvmPackages,
}:

rustPlatform.buildRustPackage rec {
  pname = "mediatoascii";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "spoorn";
    repo = "media-to-ascii";
    tag = version;
    hash = "sha256-4MfyEd07q3J+hAqgwG2QndN+I3JxxGcqs2cMyHWAOYY=";
  };

  cargoHash = "sha256-C5XyHODgipO8oMY84RTnfH/ylDnte/W2wa65fqkgWFU=";

  # The workspace also contains a Tauri desktop app (mediatoascii-app) that
  # pulls in GTK/gdk. We only want the CLI, so build just that crate.
  cargoBuildFlags = [
    "--package"
    "mediatoascii-cli"
  ];
  cargoTestFlags = [
    "--package"
    "mediatoascii-cli"
  ];

  # The crate is named mediatoascii-cli but is documented/invoked as
  # `mediatoascii`; rename the installed binary to match.
  postInstall = ''
    mv $out/bin/mediatoascii-cli $out/bin/mediatoascii
  '';

  # The opencv crate uses bindgen (needs libclang); the ffmpeg-next crate's
  # "static" feature links against the system ffmpeg via pkg-config.
  nativeBuildInputs = [
    pkg-config
    rustPlatform.bindgenHook
    clang # opencv-binding-generator shells out to the clang binary
  ];

  buildInputs = [
    ffmpeg
    opencv
    glib
  ];

  # opencv crate's clang-runtime feature locates libclang at runtime.
  env.LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";

  meta = {
    description = "Convert images and videos to ascii output (file or console)";
    homepage = "https://github.com/spoorn/media-to-ascii";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "mediatoascii";
    platforms = lib.platforms.linux;
  };
}
