{ lib, ... }:

{
  programs.bash = {
    enable = true;

    # Ring the terminal bell when a command that ran >= 15 s finishes. On
    # trigkey, tmux turns bells into E.T. push notifications
    # (../trigkey/et-notify.nix); from gmktec the bell travels back over ssh.
    # Interactive programs (editors, pagers, ssh, claude) are skipped:
    # leaving them is not "a command finished".
    #
    # A DEBUG trap notes when the first command after a prompt starts;
    # __et_bell_precmd runs last in PROMPT_COMMAND (mkAfter, after starship
    # and direnv) and re-arms the trap for the next command.
    initExtra = lib.mkAfter ''
      __et_bell_after=15
      __et_bell_armed=1
      __et_bell_start=
      __et_bell_skip=
      __et_bell_debug() {
        [ "$__et_bell_armed" = 1 ] || return
        __et_bell_armed=0
        __et_bell_start=$SECONDS
        case "''${BASH_COMMAND%% *}" in
          vi|vim|nvim|nano|less|more|man|ssh|mosh|claude|tmux|htop|top|btop|watch|bat|git) __et_bell_skip=1 ;;
          *) __et_bell_skip= ;;
        esac
      }
      __et_bell_precmd() {
        if [ -n "$__et_bell_start" ] && [ -z "$__et_bell_skip" ] &&
           [ $((SECONDS - __et_bell_start)) -ge "$__et_bell_after" ]; then
          printf '\a'
        fi
        __et_bell_start=
        __et_bell_armed=1
      }
      trap '__et_bell_debug' DEBUG
      PROMPT_COMMAND="''${PROMPT_COMMAND:+$PROMPT_COMMAND;}__et_bell_precmd"
    '';

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
    enableBashIntegration = true; # aliases ls, ll, la, lt
    icons = "auto";
    git = true;
  };

  # direnv integration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
