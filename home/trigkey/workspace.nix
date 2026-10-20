{
  pkgs,
  lib,
  inventory,
  ...
}:

# `ws` builds the tmux workspace on trigkey, or attaches to it if it exists:
# a shell and a claude window for trigkey, then the same pair over ssh for
# each remote host. Keys are already in place, so no ssh asks for a password.
#
# Windows run `ssh` through send-keys, not as the window command. When ssh
# drops, the window stays open on a trigkey shell.
#
# tmux-persist.nix restores this session after a reboot. `ws` is for a clean
# start, or for when that restore fails.
let
  session = "main";

  # The m1-mini is not in inventory.nix (it is not a NixOS host).
  remotes = {
    gmktec = {
      hostname = inventory.hosts.gmktec.address;
      user = "eric";
    };
    mac-mini = {
      hostname = "192.168.0.5";
      user = "ericsharma";
    };
  };

  window = name: cmds: ''
    tmux new-window -t "$S" -n ${name}
    ${lib.concatMapStrings (c: ''
      tmux send-keys -t "$S:${name}" ${lib.escapeShellArg c} Enter
    '') cmds}
  '';
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = remotes;
  };

  home.packages = [
    (pkgs.writeShellApplication {
      name = "ws";
      runtimeInputs = [ pkgs.tmux ];
      text = ''
        S=${session}
        if ! tmux has-session -t "$S" 2>/dev/null; then
          tmux new-session -d -s "$S" -n trigkey
          ${window "trigkey-claude" [ "claude" ]}
          ${lib.concatStrings (
            lib.mapAttrsToList (
              host: _:
              window host [ "ssh ${host}" ]
              + window "${host}-claude" [
                "ssh ${host}"
                "claude"
              ]
            ) remotes
          )}
          tmux select-window -t "$S:1"
        fi
        if [ -n "''${TMUX:-}" ]; then
          exec tmux switch-client -t "$S"
        fi
        exec tmux attach -t "$S"
      '';
    })
  ];
}
