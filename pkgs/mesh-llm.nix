{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  openssl,
  zlib,
}:

# MeshLLM is not in nixpkgs (nearest name match is the unrelated `meshlab`), and
# upstream ships only prebuilt binaries — no crates.io release and no vendored
# Cargo.lock in the tarball — so this repackages the official release artifacts
# rather than building from source.
#
# Upstream's install path is `curl https://meshllm.cloud/install.sh | sh`, which
# drops a binary in ~/.local/bin and then downloads a matching native runtime
# (patched llama.cpp shared libraries) from GitHub on first run. Both halves are
# pinned here instead: the runtime is fetched at build time and pre-installed
# into the store, so nothing reaches the network at service start.
#
# The two archives must stay version-locked. The runtime carries a `skippy_abi`
# field (0.1.32 for 0.74.0) that the host binary checks before loading the
# libraries, so bump `version` and both hashes together.

let
  version = "0.74.0";

  # The release also publishes cuda-12, cuda-13, rocm, and vulkan variants. This
  # host is a Ryzen 7 5825U whose Vega iGPU shares DDR4 bandwidth with the CPU,
  # so the CPU runtime is the right pick and avoids pulling in a mesa/Vulkan
  # userspace. Switch by changing `runtimeId` and its hash.
  runtimeId = "meshllm-native-runtime-linux-x86_64-cpu";

  # Hashes are upstream's own published .sha256 sidecars, converted to SRI.
  mesh-llm-runtime = fetchurl {
    url = "https://github.com/Mesh-LLM/mesh-llm/releases/download/v${version}/${runtimeId}.tar.gz";
    hash = "sha256-OcLotPqViAD+2K1NMr31xIbpq5NzRu4VP71nNCr8KDw=";
  };
in

stdenv.mkDerivation {
  pname = "mesh-llm";
  inherit version;

  src = fetchurl {
    url = "https://github.com/Mesh-LLM/mesh-llm/releases/download/v${version}/mesh-llm-v${version}-x86_64-unknown-linux-gnu.tar.gz";
    hash = "sha256-daYcyOHkr7zKFoJrS2wwDLy8hYyYOhyXXZerIBu1IyI=";
  };

  # The tarball is a bare `mesh-bundle/mesh-llm`; unpack the runtime alongside it.
  sourceRoot = "mesh-bundle";

  nativeBuildInputs = [ autoPatchelfHook ];

  # The host binary needs openssl 3 + libgcc; the llama.cpp libraries in the
  # runtime additionally need libstdc++ (from stdenv's cc.cc.lib, which
  # autoPatchelfHook already searches).
  buildInputs = [
    openssl
    zlib
    stdenv.cc.cc.lib
  ];

  # The runtime libraries resolve each other by SONAME within their own lib/
  # directory, so give them an rpath pointing at themselves.
  appendRunpaths = [ "${placeholder "out"}/share/mesh-llm/native-runtimes/${runtimeId}/lib" ];

  installPhase = ''
    runHook preInstall

    install -Dm755 mesh-llm $out/bin/mesh-llm

    # Stage the native runtime in the store. The service pre-installs it from
    # here into its state directory with `mesh-llm runtime install --bundle-dir`,
    # which is fully offline — verified against v${version}.
    mkdir -p $out/share/mesh-llm/native-runtimes
    tar -xzf ${mesh-llm-runtime} -C $out/share/mesh-llm/native-runtimes
    test -f $out/share/mesh-llm/native-runtimes/${runtimeId}/manifest.json

    runHook postInstall
  '';

  # Sanity-check that the patched binary actually starts before it reaches a host.
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/mesh-llm --version | grep -q "${version}"
  '';

  passthru = {
    inherit runtimeId;
    nativeRuntimes = "share/mesh-llm/native-runtimes";
  };

  meta = {
    description = "Distributed peer-to-peer LLM inference with an OpenAI-compatible API";
    homepage = "https://meshllm.cloud";
    downloadPage = "https://github.com/Mesh-LLM/mesh-llm/releases";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "mesh-llm";
    platforms = [ "x86_64-linux" ];
  };
}
