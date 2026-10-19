# Keeps ~/.claude/skills a clone of the private github:ericsharma/claude-skills
# repo, so every host has the same custom Claude Code skills.
#
# First run: clone. The dir may already exist with tool-managed folders
# (synced/, i-have-adhd/), which the repo .gitignore covers, so init in place
# instead of `git clone`. Checkout refuses to overwrite untracked files, so a
# local skill that is not in the repo yet stops the sync instead of being lost.
# Later runs: fetch + fast-forward only. Local commits or edits are never
# overwritten; the run just logs and exits 0 so activation never fails on it.
#
# Consumed by home/optional/claude-skills.nix (NixOS hosts) and
# hosts/darwin/optional/claude-skills.nix (m1-mini).
{
  writeShellApplication,
  git,
  openssh,
  coreutils,
}:

writeShellApplication {
  name = "claude-skills-sync";
  runtimeInputs = [
    git
    openssh
    coreutils
  ];
  text = ''
    url=git@github.com:ericsharma/claude-skills.git
    dir="$HOME/.claude/skills"
    mkdir -p "$dir"
    cd "$dir"

    if [ ! -d .git ]; then
      git init -q -b main
      git remote add origin "$url"
      if ! git fetch -q origin main; then
        echo "claude-skills-sync: fetch failed (offline or no GitHub key?)" >&2
        rm -rf .git
        exit 0
      fi
      if ! git checkout -q -t origin/main; then
        echo "claude-skills-sync: checkout blocked by local files in $dir" >&2
        exit 0
      fi
      git config core.hooksPath .githooks
      echo "claude-skills-sync: cloned into $dir"
      exit 0
    fi

    git fetch -q origin main || { echo "claude-skills-sync: fetch failed" >&2; exit 0; }
    git merge -q --ff-only origin/main ||
      echo "claude-skills-sync: cannot fast-forward; commit/push or rebase local changes" >&2
  '';
}
