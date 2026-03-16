{ pkgs, lib, ... }:

let
  gstackSetup = pkgs.writeShellScriptBin "gstack-setup" ''
    set -e
    GSTACK_DIR="$HOME/.claude/skills/gstack"
    SKILLS_DIR="$HOME/.claude/skills"

    mkdir -p "$SKILLS_DIR"

    if [ ! -d "$GSTACK_DIR/.git" ]; then
      echo "Cloning gstack..."
      ${pkgs.git}/bin/git clone https://github.com/garrytan/gstack.git "$GSTACK_DIR"
    else
      echo "Updating gstack..."
      (cd "$GSTACK_DIR" && ${pkgs.git}/bin/git pull --ff-only)
    fi

    cd "$GSTACK_DIR"
    echo "Installing dependencies..."
    ${pkgs.bun}/bin/bun install

    echo "Building browse binary..."
    ${pkgs.bun}/bin/bun run build || echo "Warning: browse binary build failed (non-critical for non-browse skills)"

    # Create gstack state directory
    mkdir -p "$HOME/.gstack/projects"

    # Symlink each skill directory that contains a SKILL.md
    for skill_dir in "$GSTACK_DIR"/*/; do
      if [ -f "$skill_dir/SKILL.md" ]; then
        skill_name="$(basename "$skill_dir")"
        ln -sfn "$GSTACK_DIR/$skill_name" "$SKILLS_DIR/$skill_name"
        echo "  Linked skill: $skill_name"
      fi
    done

    echo ""
    echo "gstack setup complete! Available slash commands in Claude Code:"
    echo "  /plan-ceo-review  - Founder mode: pressure-test product vision"
    echo "  /plan-eng-review  - Tech lead: architecture & test matrices"
    echo "  /review           - Staff engineer: production-ready code review"
    echo "  /ship             - Release engineer: test, push, open PR"
    echo "  /browse           - QA with headless Chromium browser"
    echo "  /qa               - QA lead: diff-aware testing"
    echo "  /qa-only          - QA reporter: test without fixing"
    echo "  /retro            - EM analytics: weekly retrospective"
  '';

  gstackRemove = pkgs.writeShellScriptBin "gstack-remove" ''
    set -e
    GSTACK_DIR="$HOME/.claude/skills/gstack"
    SKILLS_DIR="$HOME/.claude/skills"

    if [ ! -d "$GSTACK_DIR" ]; then
      echo "gstack is not installed."
      exit 0
    fi

    # Remove symlinks that point into gstack
    for link in "$SKILLS_DIR"/*/; do
      if [ -L "''${link%/}" ]; then
        target="$(readlink -f "''${link%/}")"
        if [[ "$target" == "$GSTACK_DIR"* ]]; then
          rm "''${link%/}"
          echo "  Removed link: $(basename "''${link%/}")"
        fi
      fi
    done

    rm -rf "$GSTACK_DIR"
    echo "gstack removed."
  '';

in {
  home.packages = [
    pkgs.bun
    gstackSetup
    gstackRemove
  ];

  # Use nix-provided Playwright browsers instead of letting bun download them
  # (downloaded binaries won't work on NixOS due to FHS incompatibility)
  home.sessionVariables = {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  };
}
