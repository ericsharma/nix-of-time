{
  config,
  pkgs,
  ...
}:

let
  # ── Model ────────────────────────────────────────────────────────────────────
  # Kokoro-82M (Apache 2.0) on MLX, for the E.T. iOS app's read-aloud: E.T.
  # summarizes Claude's last reply with llama-server on :8223, then speaks it
  # with this instead of the phone's AVSpeechSynthesizer voice.
  #
  # Measured on this mini next to llama-server and muscriptor: ~600 MB
  # resident, 1.75 s for ~14 s of speech once warm (6.3 s for the first
  # request, which loads the model — hence the warm-up in serve.py).
  #
  # Served by mlx-audio's OpenAI-compatible /v1/audio/speech. Pinned: 0.5.8 is
  # the newest release at least two weeks old when this was written. misaki[en]
  # is Kokoro's phonemizer and ships its own espeak-ng, so nothing from
  # Homebrew is needed.
  mlxAudio = "mlx-audio[server]==0.5.8";
  model = "mlx-community/Kokoro-82M-bf16";

  # 8222 muscriptor, 8223 chat, 8224 embeddings: adjacent on purpose, see
  # llama-server.nix.
  port = 8225;

  # LAN-wide for the same reason as llama-server.nix (trigkey's curl calls it on
  # E.T.'s behalf), and paid for the same way: a Bearer key, enforced by
  # serve.py because mlx-audio's server has no auth of its own.
  listenAddress = "0.0.0.0";

  home = config.users.users.ericsharma.home;
  cacheDir = "${home}/Library/Caches/kokoro-tts";
  logDir = "${home}/Library/Logs/kokoro-tts";

  # mlx-audio's FastAPI app, behind the key, warmed at start.
  serve = pkgs.writeText "kokoro-tts-serve.py" ''
    """mlx-audio's OpenAI-compatible TTS server, behind a Bearer key."""

    import hmac
    import json
    import os
    import sys
    import threading
    import time
    import urllib.request

    import uvicorn
    from fastapi.responses import JSONResponse
    from mlx_audio.server import app

    KEY = os.environ["TTS_API_KEY"]
    OPEN = {"/", "/v1/models"}


    @app.middleware("http")
    async def require_key(request, call_next):
        if request.method == "GET" and request.url.path in OPEN:
            return await call_next(request)
        given = request.headers.get("authorization", "")
        if not hmac.compare_digest(given.encode(), f"Bearer {KEY}".encode()):
            return JSONResponse({"error": {"message": "Invalid API key"}}, status_code=401)
        return await call_next(request)


    def warm(port, model):
        """Load the model now, so the first real request is fast."""
        body = json.dumps({"model": model, "input": "Ready.", "voice": "af_heart"}).encode()
        for _ in range(60):
            time.sleep(2)
            try:
                req = urllib.request.Request(
                    f"http://127.0.0.1:{port}/v1/audio/speech", data=body,
                    headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"})
                urllib.request.urlopen(req, timeout=120).read()
                print("kokoro-tts: warm", flush=True)
                return
            except OSError:
                continue


    if __name__ == "__main__":
        host, port, model = sys.argv[1], int(sys.argv[2]), sys.argv[3]
        threading.Thread(target=warm, args=(port, model), daemon=True).start()
        uvicorn.run(app, host=host, port=port, log_level="warning")
  '';

  # Same fail-closed secret handling as llama-server.nix; see the comments
  # there for why the wait loop and the split assignment both matter.
  wrapper = pkgs.writeShellScript "kokoro-tts-run" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.uv
        pkgs.coreutils
      ]
    }:$PATH
    mkdir -p "${logDir}" "${cacheDir}"

    secret=${config.sops.secrets."llama-server/api-key".path}
    for _ in $(seq 60); do
      if [ -r "$secret" ] && [ -s "$secret" ]; then break; fi
      sleep 1
    done
    if [ ! -r "$secret" ] || [ ! -s "$secret" ]; then
      echo "kokoro-tts: $secret still unreadable after 60s; exiting for launchd to retry" >&2
      exit 1
    fi
    TTS_API_KEY="$(cat "$secret")"
    export TTS_API_KEY

    # Model weights, uv's packages and its managed Python all stay under the
    # cache dir, so a first boot downloads once (~1 GB) and later starts reuse it.
    export HF_HOME="${cacheDir}/huggingface"
    export UV_CACHE_DIR="${cacheDir}/uv"
    export UV_PYTHON_INSTALL_DIR="${cacheDir}/python"

    exec uvx --python 3.12 --from '${mlxAudio}' --with 'misaki[en]' \
      python ${serve} ${listenAddress} ${toString port} ${model}
  '';
in
{
  environment.systemPackages = [ pkgs.uv ];

  # A daemon with `command` for the reasons in llama-server.nix and
  # muscriptor.nix (headless mini, /nix mount race at boot).
  launchd.daemons.kokoro-tts = {
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
