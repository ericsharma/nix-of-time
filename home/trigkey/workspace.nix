{
  config,
  pkgs,
  lib,
  inventory,
  ...
}:

# `ws` builds the manymux workspace (over etd, no ssh): a `shell` and a `claude` session on
# trigkey, and the same pair on each remote host. Sessions live on their own
# machine (the etd module's manymux node), so a remote one survives trigkey going
# down, and the E.T. app shows them all. Only missing sessions are started;
# running it again changes nothing. In a terminal (not inside a session), it
# then attaches to trigkey's `shell`: `Ctrl-b` then `tab`/`h` moves around.
#
# Plan: ~/et-ios/docs/PLAN-manymux.md. The tmux session `main` (tmux-persist.nix)
# is untouched and still there with `tmux attach -t main`.
let
  # The m1-mini is not in inventory.nix (it is not a NixOS host). The names
  # are also manymux's machine names (`mm add`), through these ssh aliases.
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

  # A session runs through `$SHELL -lc`, which skips ~/.zshrc. On the m1-mini,
  # `claude` exists only as an alias there, so start it by its path.
  claude = {
    gmktec = "claude";
    mac-mini = "/Users/ericsharma/.claude/local/claude";
  };

  # start <target as `mm ls` prints it> <name> [mm new arguments…]
  remote = host: ''
    start ${host}/shell shell ${host}
    start ${host}/claude claude ${host} ${claude.${host}}
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
      runtimeInputs = [ pkgs.manymux ];
      text = ''
        # The other machines through etd (no ssh), also from a shell that
        # started before MM_SSH was set.
        export MM_SSH=${config.services.etd.package}/bin/etd-ssh
        # Local sessions start in the client's directory: home, as tmux did.
        cd "$HOME"
        listing=$(mm ls 2>/dev/null || true)
        start() {
          local target=$1 name=$2
          shift 2
          # No pipe into `grep -q`: with pipefail, its early exit reads as
          # "not running" and would start a duplicate.
          if awk -v t="$target" 'NR > 1 && $1 == t { found = 1 } END { exit !found }' <<<"$listing"; then
            echo "ws: $target is running"
          else
            # One unreachable machine must not stop the others.
            mm new -d -n "$name" "$@" || echo "ws: could not start $target"
          fi
        }
        start shell shell
        start claude claude local claude
        ${lib.concatMapStrings remote (lib.attrNames remotes)}
        if [ -t 1 ] && [ -z "''${MM_SESSION:-}" ]; then
          exec mm attach shell
        fi
      '';
    })
  ];
}
