{
  config,
  lib,
  pkgs,
  ...
}:

let
  # ── The voice ────────────────────────────────────────────────────────────────
  # Piper needs two files per voice: the ONNX weights and a JSON config that
  # describes the phoneme table and sample rate. Both are pinned here rather
  # than downloaded into a home directory, so the voice is part of the system
  # closure and a rebuild on a fresh disk reproduces it exactly.
  #
  # `medium` is the quality tier to want here. `low` is noticeably robotic and
  # `high` costs several times the compute for a difference you have to listen
  # for. Measured on this box: medium runs ~8x faster than real time on 8
  # threads, so there is no reason to drop to low.
  #
  # To add a second voice, browse https://huggingface.co/rhasspy/piper-voices
  # and get the hash with:
  #   nix-prefetch-url --type sha256 <url>
  voiceBase = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium";
  voiceName = "en_US-lessac-medium";

  voiceOnnx = pkgs.fetchurl {
    url = "${voiceBase}/${voiceName}.onnx";
    sha256 = "17q1mzm6xd5i2rxx2xwqkxvfx796kmp1lvk4mwkph602k7k0kzjy";
  };

  voiceJson = pkgs.fetchurl {
    url = "${voiceBase}/${voiceName}.onnx.json";
    sha256 = "184hnvd8389xpdm0x2w6phss23v5pb34i0lhd4nmy1gdgd0rrqgg";
  };

  # Piper looks for `<model>.onnx.json` next to `<model>.onnx`, so the two
  # fetchurl outputs must share a directory. fetchurl alone cannot do that —
  # each lands at its own store path under its own name.
  voiceDir = pkgs.runCommand "piper-voice-${voiceName}" { } ''
    mkdir -p $out
    ln -s ${voiceOnnx} $out/${voiceName}.onnx
    ln -s ${voiceJson} $out/${voiceName}.onnx.json
  '';

  # ── The HTTP server ──────────────────────────────────────────────────────────
  # `pkgs.piper-tts` exposes only `bin/piper`, the one-shot CLI. The HTTP server
  # lives in the same wheel at `piper.http_server` but has no wrapper script, so
  # it needs an interpreter that can import both piper and its dependencies.
  #
  # Reusing `propagatedBuildInputs` keeps that dependency list in lockstep with
  # whatever nixpkgs decides piper needs — no hand-maintained copy to drift.
  # The interpreter itself appears in that list and must come out, because
  # withPackages takes python *modules*, not a second python.
  piperPython = pkgs.python3.withPackages (
    _: builtins.filter (p: (p.pname or "") != "python3") pkgs.piper-tts.propagatedBuildInputs
  );
in
{
  # The CLI, for one-off `piper -m ... -f out.wav` runs over SSH.
  environment.systemPackages = [ pkgs.piper-tts ];

  systemd.services.piper-http = {
    description = "Piper text-to-speech HTTP API";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    # The piper package's own site-packages. Its dependencies come from
    # piperPython; only the piper module itself needs adding by hand.
    environment.PYTHONPATH = "${pkgs.piper-tts}/${pkgs.python3.sitePackages}";

    serviceConfig = {
      ExecStart = lib.concatStringsSep " " [
        "${piperPython}/bin/python"
        "-m piper.http_server"
        # Bound to all interfaces on purpose. gmktec has no Newt tunnel and no
        # reverse proxy, so the repo's usual 127.0.0.1 rule would make this
        # unreachable from the LAN, which is the whole point of the service.
        # The firewall rule below is what actually limits who can connect.
        "--host 0.0.0.0"
        "--port 5000"
        "-m ${voiceDir}/${voiceName}.onnx"
      ];

      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 5;

      # librosa and numba want somewhere to write a JIT cache, and torch reads
      # HOME on import. Without both, the service fails on start.
      CacheDirectory = "piper";
      Environment = [ "HOME=/var/cache/piper" ];

      # Hardening. The service reads two files from the store and writes only
      # its cache dir, so it can afford a tight profile.
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };

  # LAN only. The API has no authentication — anyone who reaches it can make
  # the machine synthesise audio. Scoped the same way as llama-server on :8081.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport 5000 accept comment "piper TTS from LAN"
  '';
}
