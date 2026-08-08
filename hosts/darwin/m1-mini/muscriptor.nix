{
  config,
  pkgs,
  ...
}:

let
  # ── Paths ────────────────────────────────────────────────────────────────────
  # Everything lives under ~/Library — the service runs as the login user via
  # LaunchAgent, so this is the natural place.
  home = config.users.users.ericsharma.home;
  cacheDir = "${home}/Library/Caches/muscriptor";
  logDir = "${home}/Library/Logs/muscriptor";

  # ── Runtime wrapper ──────────────────────────────────────────────────────────
  # launchd does not inherit an interactive shell, so PATH and secrets have to
  # be set explicitly. Fetching the HF token from the System keychain at start
  # (rather than baking it into the plist) keeps the secret off disk in
  # plaintext. The System keychain is used instead of the login keychain
  # because this mini is headless/SSH-only: writing to the login keychain
  # requires a bound GUI Security Session and fails over SSH with "User
  # interaction is not allowed", even run interactively. Writing to the
  # System keychain only needs sudo, which works fine over SSH. One-time
  # bootstrap: `sudo security add-generic-password -a $USER -s
  # muscriptor-hf-token -w <token> /Library/Keychains/System.keychain`.
  #
  # /usr/bin/security is Apple's binary, not a nixpkgs one, so the full path is
  # hard-coded to avoid a PATH-ordering surprise.
  wrapper = pkgs.writeShellScript "muscriptor-run" ''
    set -euo pipefail
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.uv
        pkgs.fluidsynth
        pkgs.coreutils
      ]
    }:$PATH
    export HF_TOKEN="$(/usr/bin/security find-generic-password -a ericsharma -s muscriptor-hf-token -w /Library/Keychains/System.keychain)"
    export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
    export HF_HOME="${cacheDir}/huggingface"
    mkdir -p "${logDir}" "${cacheDir}/huggingface"
    exec uvx muscriptor serve \
      --model medium \
      --device mps \
      --host 0.0.0.0 \
      --port 8222
  '';
in
{
  # System-wide install of the two binaries the wrapper depends on. `uv`
  # provides the `uvx muscriptor` launcher recommended by upstream; `fluidsynth`
  # is required by the /auralize endpoint — without it, WAV export is silent.
  environment.systemPackages = with pkgs; [
    uv
    fluidsynth
  ];

  # ── LaunchDaemon ─────────────────────────────────────────────────────────────
  # Rendered to /Library/LaunchDaemons/org.nixos.muscriptor.plist at each
  # `darwin-rebuild switch`. A *daemon* (system domain), not a user LaunchAgent:
  # this mini is headless and sits at a locked screen with no active GUI
  # session, and launchd defers (never actually runs) RunAtLoad/KeepAlive jobs
  # in a user's gui/<uid> domain until that session is genuinely active —
  # confirmed via `launchctl print gui/501/org.nixos.muscriptor` showing
  # `runs = 0` / `pended nondemand spawn = speculative` after activation. The
  # system domain has no such dependency, which is why the original hand-rolled
  # LaunchDaemon always worked. UserName/GroupName run the process as
  # ericsharma rather than root, matching the original.
  launchd.daemons.muscriptor = {
    serviceConfig = {
      ProgramArguments = [ "${wrapper}" ];
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
