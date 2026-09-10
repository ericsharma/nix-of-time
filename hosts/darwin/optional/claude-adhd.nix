{
  config,
  pkgs,
  i-have-adhd,
  ...
}:

let
  adhd = pkgs.callPackage ../../../pkgs/claude-adhd.nix { inherit i-have-adhd; };

  user = config.system.primaryUser;
  claudeDir = "${config.users.users.${user}.home}/.claude";
in
{
  # Same result as home/optional/claude-adhd.nix, without home-manager — the
  # darwin hosts in this repo are not under home-manager, so the linking is done
  # by hand at activation.
  #
  # nix-darwin removed `postUserActivation`: every activation script now runs as
  # root, and an assertion fires if you try to use the old option. Drop to the
  # login user explicitly instead. /usr/bin/sudo is hard-coded (like
  # /usr/bin/security in m1-mini/muscriptor.nix) because activation runs with a
  # scrubbed PATH.
  system.activationScripts.postActivation.text = ''
    echo "installing Claude Code ADHD output rules for ${user}..." >&2
    /usr/bin/sudo -u ${user} ${pkgs.coreutils}/bin/mkdir -p "${claudeDir}"
    /usr/bin/sudo -u ${user} ${pkgs.coreutils}/bin/ln -sfn \
      "${adhd.rules}" "${claudeDir}/adhd-rules.md"
    /usr/bin/sudo -u ${user} ${adhd.ensureImport} "${claudeDir}"
  '';
}
