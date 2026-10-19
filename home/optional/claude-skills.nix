{ pkgs, lib, ... }:

let
  sync = pkgs.callPackage ../../pkgs/claude-skills-sync.nix { };
in
{
  # `claude-skills-sync` on PATH for a manual pull; gitleaks for the repo's
  # pre-commit hook.
  home.packages = [
    sync
    pkgs.gitleaks
  ];

  # Clone on first deploy. Never fails activation (offline, no key, etc.).
  home.activation.claudeSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${sync}/bin/claude-skills-sync || true
  '';

  # Pick up skills edited and pushed from another host.
  systemd.user.services.claude-skills-sync = {
    Unit.Description = "Pull ~/.claude/skills from GitHub";
    Service = {
      Type = "oneshot";
      ExecStart = "${sync}/bin/claude-skills-sync";
    };
  };
  systemd.user.timers.claude-skills-sync = {
    Unit.Description = "Pull ~/.claude/skills every 15 minutes";
    # OnCalendar, not OnUnitActiveSec: the latter never fires when the timer
    # starts after boot (first deploy) and the service has never run.
    Timer = {
      OnCalendar = "*:0/15";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
