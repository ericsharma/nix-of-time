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

      # Common shortcuts
      ll = "ls -lah";
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

  # direnv integration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
