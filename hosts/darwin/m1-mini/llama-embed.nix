{
  config,
  pkgs,
  ...
}:

let
  # ── Model ────────────────────────────────────────────────────────────────────
  # Qwen3-Embedding-0.6B, Apache 2.0, the official Qwen GGUF. Serves
  # /v1/embeddings for nam-shub (related ideas + semantic search). Q8_0 is
  # ~640 MB, so it sits next to the 9B chat model and muscriptor without
  # pressure. 1024-dim output, last-token pooling.
  #
  # Query vs document: queries get `Instruct: <task>\nQuery:<text>`, documents
  # go in bare. Do NOT append <|endoftext|> client-side — the GGUF sets
  # add_eos_token, so llama-server already appends it, and a second one moves
  # scores off the reference values. Verified on this box against the Qwen
  # README example: [[0.7642, 0.1425], [0.1360, 0.6004]] vs reference
  # [[0.7646, 0.1414], [0.1355, 0.6000]].
  modelRepo = "Qwen/Qwen3-Embedding-0.6B-GGUF";
  modelQuant = "Q8_0";
  modelAlias = "qwen3-embedding-0.6b";

  # ── Context ──────────────────────────────────────────────────────────────────
  # 8192 split across 2 slots = 4096 tokens max per input. Highlights are
  # ≤600 words (~800 tokens), so this is 5x headroom. The physical batch must
  # hold a whole input for embeddings, hence -b/-ub match the per-slot size.
  # Measured: a 64-input batch of ~400-token texts returns in 1.2 s.
  ctxSize = 8192;
  parallel = 2;
  perSlot = ctxSize / parallel;

  # 8223 is chat. A separate daemon rather than llama-server's router mode:
  # each model restarts independently and the chat service keeps the exact
  # flags it was benchmarked with.
  port = 8224;
  listenAddress = "0.0.0.0";

  home = config.users.users.ericsharma.home;
  cacheDir = "${home}/Library/Caches/llama-server";
  logDir = "${home}/Library/Logs/llama-embed";

  # Same fail-closed wrapper shape as llama-server.nix (read its comments for
  # why the wait loop and the split assignment both matter). Same key: callers
  # use one Bearer token for both ports.
  wrapper = pkgs.writeShellScript "llama-embed-run" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.unstable.llama-cpp
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
      echo "llama-embed: $secret still unreadable after 60s; exiting for launchd to retry" >&2
      exit 1
    fi
    LLAMA_API_KEY="$(cat "$secret")"
    export LLAMA_API_KEY

    export LLAMA_CACHE="${cacheDir}"

    exec llama-server \
      -hf ${modelRepo}:${modelQuant} \
      --alias ${modelAlias} \
      --embedding \
      --pooling last \
      -c ${toString ctxSize} \
      -np ${toString parallel} \
      -b ${toString perSlot} \
      -ub ${toString perSlot} \
      -ngl 999 \
      --metrics \
      --host ${listenAddress} \
      --port ${toString port}
  '';
in
{
  # Daemon + `command` for the same reasons as llama-server.nix: headless box
  # (system domain), and wait4path so boot doesn't race the /nix mount.
  launchd.daemons.llama-embed = {
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
