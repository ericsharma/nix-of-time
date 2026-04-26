{ ... }:

{
  programs.bash = {
    enable = true;

    # Preserve existing PATH
    profileExtra = ''
      export PATH="$HOME/.local/bin:$PATH"
    '';

    shellAliases = {
      # NixOS management (nh = Nix Helper; shows nvd diff before activation)
      rebuild = "nh os switch";
      rebuild-docker = "nixos-rebuild switch --flake ~/nixos-config#docker-services --target-host root@10.0.100.10";

      # Common shortcuts (ls/ll/la/lt are aliased to eza by programs.eza)
      cat = "bat";

      # Git shortcuts
      gs = "git status";
      gd = "git diff";
      gl = "git log";
    };
  };

  programs.bat = {
    enable = true;
    config = {
      theme = "Nord";
      style = "numbers,changes,header";
    };
  };

  programs.eza = {
    enable = true;
    enableBashIntegration = true;  # aliases ls, ll, la, lt
    icons = "auto";
    git = true;
  };

  # direnv integration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
