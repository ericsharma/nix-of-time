{
  config,
  pkgs,
  ...
}:

let
  # ── Model ────────────────────────────────────────────────────────────────────
  # OmniVoice (k2-fsa, Apache 2.0): zero-shot TTS with voice cloning, voice
  # design and 600+ languages. ~613M params, fp16 on MPS. Kokoro (:8225)
  # stays the fast English read-aloud voice for E.T.; this one is for cloning
  # and design, used by hand through its Gradio web UI.
  #
  # Pinned: omnivoice 0.2.1 is the newest release, and torch 2.8.0 is the
  # version the README installs for Apple Silicon.
  omnivoice = "omnivoice==0.2.1";
  torch = "torch==2.8.0";
  torchaudio = "torchaudio==2.8.0";

  # 8222 muscriptor, 8223 chat, 8224 embeddings, 8225 Kokoro.
  port = 8226;

  # LAN-wide so the web UI opens from any device; this mini is headless.
  # Gradio's demo has no auth, so anyone on the LAN can use it.
  listenAddress = "0.0.0.0";

  home = config.users.users.ericsharma.home;
  cacheDir = "${home}/Library/Caches/omnivoice";
  logDir = "${home}/Library/Logs/omnivoice";

  wrapper = pkgs.writeShellScript "omnivoice-run" ''
    set -euo pipefail
    # ffmpeg: librosa/pydub decode non-WAV reference clips through it.
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.uv
        pkgs.coreutils
        pkgs.ffmpeg-headless
      ]
    }:$PATH
    mkdir -p "${logDir}" "${cacheDir}"

    # Weights (~3.3 GB), uv's packages and its managed Python stay under the
    # cache dir, so only the first boot downloads.
    export HF_HOME="${cacheDir}/huggingface"
    export UV_CACHE_DIR="${cacheDir}/uv"
    export UV_PYTHON_INSTALL_DIR="${cacheDir}/python"
    export GRADIO_ANALYTICS_ENABLED=False
    # Ops MPS lacks fall back to CPU instead of raising.
    export PYTORCH_ENABLE_MPS_FALLBACK=1

    # --no-asr: skips Whisper large-v3-turbo (~1.6 GB more RAM next to the
    # chat model). Voice cloning then needs the reference clip's transcript
    # typed in.
    exec uvx --python 3.12 --from '${omnivoice}' \
      --with '${torch}' --with '${torchaudio}' \
      omnivoice-demo --device mps --no-asr \
      --ip ${listenAddress} --port ${toString port}
  '';
in
{
  environment.systemPackages = [ pkgs.uv ];

  # A daemon with `command` for the reasons in llama-server.nix and
  # muscriptor.nix (headless mini, /nix mount race at boot).
  launchd.daemons.omnivoice = {
    command = "${wrapper}";
    serviceConfig = {
      UserName = "ericsharma";
      GroupName = "staff";
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${logDir}/stdout.log";
      StandardErrorPath = "${logDir}/stderr.log";
      WorkingDirectory = home;
      ProcessType = "Interactive";
    };
  };
}
