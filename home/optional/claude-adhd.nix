{
  pkgs,
  lib,
  i-have-adhd,
  ...
}:

let
  adhd = pkgs.callPackage ../../pkgs/claude-adhd.nix { inherit i-have-adhd; };
in
{
  # Read-only store symlink — the rules themselves are never hand-edited.
  home.file.".claude/adhd-rules.md".source = adhd.rules;

  # CLAUDE.md stays a real, writable file (Claude Code edits it), so only the
  # `@adhd-rules.md` import line is enforced here. Runs after writeBoundary so
  # adhd-rules.md is already in place when the import starts pointing at it.
  home.activation.claudeAdhdImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${adhd.ensureImport} "$HOME/.claude"
  '';
}
