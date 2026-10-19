{ config, pkgs, ... }:

let
  sync = pkgs.callPackage ../../../pkgs/claude-skills-sync.nix { };
  user = config.system.primaryUser;
in
{
  # Same result as home/optional/claude-skills.nix, without home-manager.
  environment.systemPackages = [
    sync
    pkgs.gitleaks
  ];

  # Activation runs as root with a scrubbed PATH; drop to the login user (see
  # claude-adhd.nix). -H so the clone lands in the user's $HOME. Uses the
  # user's own ~/.ssh key for GitHub. Never fails activation.
  system.activationScripts.postActivation.text = ''
    echo "syncing Claude Code skills for ${user}..." >&2
    /usr/bin/sudo -u ${user} -H ${sync}/bin/claude-skills-sync || true
  '';

  # Pick up skills edited and pushed from another host.
  launchd.user.agents.claude-skills-sync.serviceConfig = {
    ProgramArguments = [ "${sync}/bin/claude-skills-sync" ];
    StartInterval = 900;
    RunAtLoad = true;
    StandardErrorPath = "/tmp/claude-skills-sync.log";
  };
}
