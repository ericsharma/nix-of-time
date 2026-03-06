{ ... }:

{
  programs.bash = {
    enable = true;

    # Preserve existing PATH
    profileExtra = ''
      export PATH="$HOME/.local/bin:$PATH"
    '';

    shellAliases = {
      # NixOS management
      rebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#$(hostname)";

      # Common shortcuts
      ll = "ls -lah";

      # Git shortcuts
      gs = "git status";
      gd = "git diff";
      gl = "git log";
    };
  };

  # direnv integration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
