{ lib, pkgs, ... }:

# MeshLLM — local OpenAI-compatible inference endpoint.
#
# This module lives in hosts/nixos/gmktec/ rather than hosts/nixos/optional/ on
# purpose. trigkey globs every file under optional/ with listFilesRecursive and
# those modules carry no enable flags, so a file there would silently start
# MeshLLM on trigkey too. Nothing here is wanted on that host.
#
# Mesh participation is deliberately OFF: no --publish, no --auto, no --join, so
# this host neither advertises its compute nor discovers peers. It is a private
# endpoint. Turning discovery on is a real bandwidth and privacy decision — make
# it explicitly by adding the flag, not by accident.
#
# Exposure: bound to 127.0.0.1 and not in the firewall. gmktec has no Newt
# tunnel (Pangolin runs on trigkey only), so reaching this from elsewhere means
# either an SSH tunnel or an explicit decision to open a scoped nftables rule.

let
  cfg = {
    apiPort = 9337; # OpenAI-compatible API
    consolePort = 3131; # management console/API, loopback-only upstream
    stateDir = "/var/lib/mesh-llm";
  };

  pkg = pkgs.mesh-llm;

  # A startup model is mandatory, not a preference. `mesh-llm serve` with no
  # [[models]] entry logs "needs at least one startup model" and exits 0
  # immediately — there is no headless idle mode. Verified on this host against
  # 0.74.0 in all three modes (serve, on_demand, client). Upstream's docs claim a
  # "ready_idle" state; that only holds for an interactive TTY session, not under
  # systemd. So removing this block does not give an idle daemon, it gives a unit
  # that will not stay running.
  #
  # Qwen3-4B Q4_K_M is ~2.5 GB and downloads once into the state dir on first
  # start. Swap it with a ref from `mesh-llm models search --catalog <query>`.
  configToml = pkgs.writeText "mesh-llm-config.toml" ''
    # Managed by NixOS — edits here are overwritten on rebuild.
    mode = "serve"

    [[models]]
    model = "unsloth/Qwen3-4B-GGUF@main:Q4_K_M"

    [models.hardware]
    # This build ships only the CPU native runtime, so keep everything off the
    # GPU. gpu_layers = 0 avoids a probe for a device that has no runtime here.
    model_runtime = "cpu"
    gpu_layers = 0
    mmap = true

    [defaults]
    # best_effort: a model that fails to load leaves the server up and degraded
    # rather than taking the whole unit down.
    startup_failure_policy = "best_effort"
  '';
in

{
  # ── Service account ──────────────────────────────────────────────────────────
  users.users.mesh-llm = {
    isSystemUser = true;
    group = "mesh-llm";
    home = cfg.stateDir;
    description = "MeshLLM inference server";
  };
  users.groups.mesh-llm = { };

  # ── Runtime state ────────────────────────────────────────────────────────────
  # Models are large and re-downloadable, so this is on the internal NVMe (937 GB,
  # mostly empty). It must NOT go under /mnt/backup — that disk is the only
  # off-machine copy of trigkey's data and is not for service storage.
  systemd.services.mesh-llm = {
    description = "MeshLLM local inference server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      MESH_LLM_CONFIG = configToml;
      MESH_LLM_DATA_DIR = cfg.stateDir;
      # The native runtime cache root is XDG-derived, NOT settable via
      # MESH_LLM_RUNTIME_ROOT or MESH_LLM_DATA_DIR — both are ignored for this
      # path (verified against 0.74.0). XDG_CACHE_HOME is what actually moves it,
      # so pin it inside the state dir and install to the matching subpath below.
      XDG_CACHE_HOME = "${cfg.stateDir}/cache";
      # Models land in the HF cache; keep it inside the state dir so StateDirectory
      # owns the whole footprint and nothing lands in a root-owned home.
      HF_HUB_CACHE = "${cfg.stateDir}/hf";
      HOME = cfg.stateDir;
    };

    serviceConfig = {
      Type = "simple";

      # A static system user, NOT DynamicUser. DynamicUser=yes makes systemd
      # bind-mount StateDirectory with `noexec`, and mesh-llm dlopen()s the
      # llama.cpp shared libraries out of that directory — the exec mapping is
      # refused and the server dies with "failed to map segment from shared
      # object". Verified on this host: the mount shows
      # `rw,nosuid,nodev,noexec,idmapped` under DynamicUser and is clean without
      # it. Everything else below still applies, so this costs isolation between
      # restarts but nothing else.
      User = "mesh-llm";
      Group = "mesh-llm";
      StateDirectory = "mesh-llm";
      StateDirectoryMode = "0750";
      WorkingDirectory = cfg.stateDir;

      # Pre-install the pinned native runtime from the store into the versioned
      # cache. --bundle-dir makes this fully offline, so the unit does not race
      # the network on boot and an upstream outage cannot break a restart.
      # --cache-dir must match the XDG-derived path `serve` reads, or the server
      # starts, finds no runtime, and tries to download one over the network.
      ExecStartPre = ''
        ${lib.getExe pkg} runtime install \
          --bundle-dir ${pkg}/${pkg.passthru.nativeRuntimes}/${pkg.passthru.runtimeId} \
          --cache-dir ${cfg.stateDir}/cache/mesh-llm/native-runtimes
      '';

      ExecStart = ''
        ${lib.getExe pkg} serve \
          --port ${toString cfg.apiPort} \
          --console ${toString cfg.consolePort} \
          --log-format json
      '';

      Restart = "on-failure";
      RestartSec = 5;

      # First start downloads the model (~2.5 GB) before the API comes up. The
      # default 90 s start timeout would kill it mid-download on a slow link;
      # subsequent starts hit the cache and are fast.
      TimeoutStartSec = "30min";

      # ── Hardening ────────────────────────────────────────────────────────────
      # Not MemoryDenyWriteExecute — llama.cpp maps executable pages for its
      # compute kernels and would fail to load the runtime.
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged @resources"
      ];

      # Inference will happily saturate all 16 threads. Leave headroom so the
      # nightly restic window (01:30–04:30) and SSH stay responsive.
      CPUWeight = 50;
      IOWeight = 50;
    };

    unitConfig.StartLimitIntervalSec = 0;
  };

  # The CLI on PATH talks to the running service and manages models. It reads the
  # same config the unit does, so `mesh-llm status` works for an admin over SSH.
  environment.systemPackages = [ pkg ];
  environment.variables.MESH_LLM_CONFIG = "${configToml}";

  # No firewall rule on purpose. Reach the API over an SSH tunnel:
  #   ssh -N -L 9337:127.0.0.1:9337 eric@192.168.0.51
  # then point any OpenAI client at http://127.0.0.1:9337/v1
}
