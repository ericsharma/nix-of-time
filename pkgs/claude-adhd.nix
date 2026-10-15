# ADHD-friendly output rules for Claude Code, from github:ayghri/i-have-adhd.
#
# Upstream ships the text as a *skill* with `disable-model-invocation: true`
# and a `/i-have-adhd` trigger, which makes it opt-in once per session. We want
# it always on, so the text goes next to ~/.claude/CLAUDE.md instead and is
# pulled in with an `@adhd-rules.md` import line. Claude Code reads CLAUDE.md at
# the start of every session in every project, so the rules load with no
# command typed.
#
# Consumed by home/optional/claude-adhd.nix (NixOS hosts, via home-manager) and
# hosts/darwin/optional/claude-adhd.nix (m1-mini, via nix-darwin activation).
{
  runCommand,
  writeShellScript,
  gawk,
  i-have-adhd,
}:

{
  # Upstream's YAML frontmatter is skill metadata (name, description, license).
  # It carries no meaning inside CLAUDE.md, so drop everything up to and
  # including the closing `---`. `test -s` fails the build rather than shipping
  # an empty file if upstream ever reshapes the header.
  rules = runCommand "claude-adhd-rules.md" { } ''
    ${gawk}/bin/awk 'f { print } /^---$/ { if (++n == 2) f = 1 }' \
      ${i-have-adhd}/skills/i-have-adhd/SKILL.md > $out
    test -s $out
  '';

  # ~/.claude/CLAUDE.md cannot be a store symlink: Claude Code writes its own
  # skill index into it. So manage only the single import line, idempotently, at
  # the top of the file. $1 is the .claude directory.
  ensureImport = writeShellScript "claude-adhd-ensure-import" ''
    set -eu
    dir="$1"
    md="$dir/CLAUDE.md"
    mkdir -p "$dir"
    [ -e "$md" ] || : > "$md"
    if ! grep -qxF '@adhd-rules.md' "$md"; then
      printf '@adhd-rules.md\n\n' | cat - "$md" > "$md.adhd-tmp"
      mv "$md.adhd-tmp" "$md"
    fi
  '';
}
