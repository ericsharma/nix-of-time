{ lib, pkgs, ... }:

# tmux survives a trigkey reboot. trigkey is the always-on base: one tmux
# session with a window per ssh to gmktec and other hosts, attached from the
# laptop. A reboot ends the server, so:
#
# - tmux-resurrect saves windows, panes, paths and scrollback, and restores
#   them. `@resurrect-processes 'ssh'` runs each pane's ssh command again.
# - tmux-continuum saves every 15 min and restores when the server starts.
# - tmux-server.service starts the server at boot (linger, ../../hosts/nixos/
#   common), so `tmux attach` works with nobody logged in. Its ExecStop saves
#   once more before the server ends, so a reboot loses nothing.
#
# Running programs do not come back, only their command lines. Scrollback
# comes back as text.
let
  resurrect = pkgs.tmuxPlugins.resurrect;
  tmux = "${pkgs.tmux}/bin/tmux";
in
{
  programs.tmux.plugins = [
    {
      plugin = resurrect;
      extraConfig = ''
        set -g @resurrect-capture-pane-contents 'on'
        set -g @resurrect-processes 'ssh'
      '';
    }
  ];

  # continuum runs its autosave from status-right, so it must load after
  # ../common/tmux.nix sets status-right. As a programs.tmux.plugins entry it
  # loads before extraConfig, and the autosave never runs. Hence mkAfter.
  #
  # exit-empty off keeps the server up with no sessions, so the boot unit can
  # start it empty and continuum restores into it.
  programs.tmux.extraConfig = lib.mkAfter ''
    set -g exit-empty off
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '15'
    run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
  '';

  systemd.user.services.tmux-server = {
    Unit = {
      Description = "tmux server, restored by tmux-continuum";
      # A restart runs ExecStop, which ends the server and every session in
      # it. Never do that on a home-manager switch.
      X-RestartIfChanged = false;
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      # A no-op when a server already runs (for example one started by hand).
      ExecStart = "${tmux} start-server";
      ExecStop = [
        "${resurrect}/share/tmux-plugins/resurrect/scripts/save.sh quiet"
        "${tmux} kill-server"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };
}
