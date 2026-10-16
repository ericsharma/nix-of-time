{
  config,
  pkgs,
  ...
}:

let
  # ── Model ────────────────────────────────────────────────────────────────────
  # Qwen3.5-9B, Apache 2.0. Chosen over the alternatives at this size because it
  # is the only one that wins on all four axes this box cares about: native tool
  # calling (the `<tool_call><function=…>` XML dialect, which llama.cpp's PEG
  # parser understands), a genuinely permissive licence, an architecture the
  # pinned llama.cpp can load, and a Q4_K_M that leaves headroom next to
  # muscriptor.
  #
  # GGUF arch is "qwen35" → LLM_ARCH_QWEN35. This is why the service runs
  # pkgs.unstable.llama-cpp and not pkgs.llama-cpp: nixpkgs 25.11 pins b6981,
  # whose arch table stops at QWEN3/QWEN3VL and which rejects this model
  # outright. unstable's b9190 registers QWEN35 and QWEN35MOE. Before changing
  # either the model or the llama-cpp source, check they still agree:
  #   grep LLM_ARCH_QWEN35 <llama-cpp-src>/src/llama-arch.h
  # A mismatch shows up as a load failure, not a config error.
  #
  # Q4_K_M is 5.68 GB on disk, ~6.25 GB resident. Measured on this mini with
  # these exact flags on b9190: 100 tok/s prompt, 9.0 tok/s generation. That
  # generation figure is not a tuning failure — a base M1 has ~68 GB/s of memory
  # bandwidth and decoding is bandwidth-bound, so 68/5.68 ≈ 12 tok/s is the hard
  # ceiling and we sit at ~75% of it. No flag recovers more; only a smaller
  # model does.
  #
  # Budget accordingly: ~63 output tokens per normalized CSV row means ~7 s/row.
  # Batch many rows per request (the prompt side is 11x faster than the generate
  # side), and prefer deterministic parsing for rows that match known merchants
  # — send the model only what actually needs judgement.
  #
  # To trade accuracy for ~2x throughput, swap to Qwen3.5-4B (2.74 GB) — same
  # template, same tool-call dialect, one-line change here:
  #   modelRepo = "unsloth/Qwen3.5-4B-GGUF";
  modelRepo = "unsloth/Qwen3.5-9B-GGUF";
  modelQuant = "Q4_K_M";
  modelAlias = "qwen3.5-9b";

  # ── Context ──────────────────────────────────────────────────────────────────
  # 32k of the model's 262k native window. Context is not free: llama.cpp
  # allocates the whole KV cache up front at this size, so asking for 262k on a
  # 16 GB machine fails at startup rather than degrading. 32k holds a few
  # thousand CSV rows per request, which is the actual workload here.
  ctxSize = 32768;

  # 8222 is muscriptor. Keep these adjacent so the mini's two inference services
  # are obvious from a single `lsof -i :822x`.
  port = 8223;

  # ── Exposure ─────────────────────────────────────────────────────────────────
  # This deliberately breaks the repo-wide "bind 127.0.0.1, expose via Pangolin"
  # rule in CLAUDE.md: the whole point of this service is that any device on
  # 192.168.0.0/24 can use the mini's GPU, and routing LAN inference through a
  # public reverse proxy would be worse on both latency and attack surface.
  # The trade is paid for with mandatory API-key auth (see the wrapper) rather
  # than with a loopback bind. Nothing here opens a port to the internet.
  listenAddress = "0.0.0.0";

  home = config.users.users.ericsharma.home;
  cacheDir = "${home}/Library/Caches/llama-server";
  logDir = "${home}/Library/Logs/llama-server";

  # ── Runtime wrapper ──────────────────────────────────────────────────────────
  # Same shape as muscriptor.nix: launchd gives us no interactive shell, so PATH
  # and secrets are set explicitly. Unlike muscriptor, the secret comes from
  # sops rather than the System keychain — no `security add-generic-password`
  # bootstrap, and the key is version-controlled and readable by every other
  # host on the LAN that needs to *call* this server. muscriptor still uses the
  # keychain; converting it is a separate change.
  #
  # The `set -euo pipefail` interaction is deliberate and is the opposite of the
  # call made in muscriptor.nix. If the secret is missing or undecryptable the
  # wrapper waits, then aborts, launchd retries, and the port never opens. That
  # is what we want: this listener is on 0.0.0.0 with the macOS application
  # firewall disabled, so failing closed beats silently serving an
  # unauthenticated model to the LAN.
  #
  # Two things below are load-bearing for that promise, and the original version
  # of this file had neither — stderr.log records a boot that sailed straight
  # past a missing secret and started the server regardless. `set -e` alone does
  # not buy fail-closed; see the wait loop and the split assignment.
  wrapper = pkgs.writeShellScript "llama-server-run" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.unstable.llama-cpp
        pkgs.coreutils
      ]
    }:$PATH
    mkdir -p "${logDir}" "${cacheDir}"

    # ── Wait for sops ──────────────────────────────────────────────────────────
    # launchd has no ordering edge to sops-nix activation. RunAtLoad starts this
    # daemon the moment launchd loads the plist, which on a cold boot is before
    # /run/secrets is populated. That is not hypothetical — the first line this
    # service ever wrote to stderr.log was
    #   cat: /run/secrets/llama-server/api-key: No such file or directory
    # because `set -euo pipefail` aborted on the missing file, exactly as the
    # comment above intends. KeepAlive retried until activation caught up, so it
    # self-healed, but every reboot left a window where the port was closed and
    # LAN callers got a refused connection rather than a 401.
    #
    # So poll rather than race. Bounded, not infinite: if the secret genuinely
    # cannot be decrypted — rotated host key, botched re-encrypt, wrong owner —
    # we want a non-zero exit and a launchd retry, not a daemon launchd reports
    # as alive while it blocks forever on a file that will never arrive. Both
    # tests matter: -r catches the sops-nix default of root:0400 (the wrapper
    # runs as ericsharma), -s catches a truncated or empty decrypt.
    secret=${config.sops.secrets."llama-server/api-key".path}
    for _ in $(seq 60); do
      if [ -r "$secret" ] && [ -s "$secret" ]; then break; fi
      sleep 1
    done
    if [ ! -r "$secret" ] || [ ! -s "$secret" ]; then
      echo "llama-server: $secret still unreadable after 60s; exiting for launchd to retry" >&2
      exit 1
    fi

    # Passed by environment, never as --api-key on argv: argv is world-readable
    # via `ps` to any local account, whereas another user's environment is not.
    #
    # Assign first, export second — deliberately not `export VAR="$(cat ...)"`.
    # In that one-liner the exit status belongs to `export`, which is always 0,
    # so a failing `cat` is swallowed and `set -e` never fires. That is not
    # theoretical: it is precisely how the boot logged above got past a missing
    # secret and went on to launch llama-server anyway. Split this way, the
    # assignment is its own simple command, so a failed read aborts the wrapper
    # and makes the fail-closed promise in the header comment actually true.
    LLAMA_API_KEY="$(cat "$secret")"
    export LLAMA_API_KEY

    # -hf resolves into $LLAMA_CACHE and reuses the file on every later start,
    # so the 5.68 GB fetch happens once. First boot after a fresh deploy will
    # therefore sit in "downloading" for a while before the port opens; that is
    # not a hang.
    export LLAMA_CACHE="${cacheDir}"

    # Qwen3.5-9B is a vision-language model, and -hf helpfully pulls its
    # mmproj-BF16 projector alongside the weights unless told not to. This
    # workload is text-only, so --no-mmproj saves ~500 MB of download and keeps
    # the vision tower out of a memory budget that has none to spare.
    #
    # --reasoning off matters more than it looks: the chat template leaves
    # thinking off by default, but llama.cpp's own --reasoning defaults to
    # 'auto' and turns it back on, which cost ~300 wasted tokens per call in
    # testing. At this box's generation speed that is tens of seconds per row.

    exec llama-server \
      -hf ${modelRepo}:${modelQuant} \
      --alias ${modelAlias} \
      --no-mmproj \
      -c ${toString ctxSize} \
      -ngl 999 \
      -fa on \
      -ctk q8_0 \
      -ctv q8_0 \
      -np 1 \
      --jinja \
      --reasoning off \
      --cache-reuse 256 \
      --metrics \
      --host ${listenAddress} \
      --port ${toString port}
  '';
in
{
  # Built with GGML_METAL=TRUE and LLAMA_METAL_EMBED_LIBRARY=TRUE on
  # aarch64-darwin, so the Metal backend needs no extra flags and no shader
  # files alongside the binary. Installing it system-wide also puts
  # `llama-bench` and `llama-cli` on PATH — and it must be the *same* unstable
  # package the daemon runs, or hand-testing a flag will validate a different
  # binary than the service uses.
  environment.systemPackages = [ pkgs.unstable.llama-cpp ];

  # Decrypted to /run/secrets/llama-server/api-key at activation. owner must be
  # the account launchd runs the daemon as — sops-nix defaults secrets to
  # root:0400, which the wrapper (running as ericsharma) could not read.
  sops.secrets."llama-server/api-key" = {
    owner = "ericsharma";
  };

  # ── LaunchDaemon ─────────────────────────────────────────────────────────────
  # A daemon, not a user LaunchAgent, for exactly the reason documented at length
  # in muscriptor.nix: this mini is headless and sits at a locked screen, and
  # launchd never actually spawns RunAtLoad/KeepAlive jobs in an inactive
  # gui/<uid> domain. UserName/GroupName drop it to ericsharma so the model cache
  # under ~/Library stays owned by the login user.
  #
  # `command`, not `serviceConfig.ProgramArguments`: nix-darwin wraps `command`
  # in `/bin/wait4path /nix/store && exec …`. A bare store path in
  # ProgramArguments races the /nix APFS volume mount at boot — launchd finds no
  # executable, records exit 78 (EX_CONFIG), parks the job in "spawn scheduled"
  # waiting for the path to appear, and never retries. That is how port 8223
  # stayed refused for a full day after the 2026-10-15 reboot.
  launchd.daemons.llama-server = {
    command = "${wrapper}";
    serviceConfig = {
      UserName = "ericsharma";
      GroupName = "staff";
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${logDir}/stdout.log";
      StandardErrorPath = "${logDir}/stderr.log";
      WorkingDirectory = home;
      # Interactive keeps launchd from applying background CPU/IO throttling —
      # the same reason muscriptor sets it. A throttled inference server on an
      # 8-core M1 GPU is very obviously slower.
      ProcessType = "Interactive";
    };
  };
}
