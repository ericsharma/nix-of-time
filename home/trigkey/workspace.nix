{
  config,
  pkgs,
  lib,
  ...
}:

# `ws` builds the manymux workspace (over etd, no ssh): a `shell` and a
# `claude` session on trigkey, and the same pair on every other machine of the
# etd network (`mm hosts`, which etd keeps equal to the network), so a machine
# that joins gets its pair with no change here. Sessions live on their own
# machine (the etd module's manymux node), so a remote one survives trigkey
# going down, and the E.T. app shows them all. Only missing sessions are
# started; running it again changes nothing. In a terminal (not inside a
# session), it then attaches to trigkey's `shell`: `Ctrl-b` then `tab`/`h`
# moves around.
#
# Plan: ~/et-ios/docs/PLAN-manymux.md. It replaced the tmux workspace and the
# ssh names it used (both removed 2026-10-22).
let
  # A session runs through `$SHELL -lc`, which skips ~/.zshrc. On the m1-mini,
  # `claude` exists only as an alias there, so start it by its path. Other
  # machines: `claude`.
  claude = {
    mac-mini = "/Users/ericsharma/.claude/local/claude";
  };
in
{
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
        claude_on() {
          case "$1" in
          ${lib.concatStrings (
            lib.mapAttrsToList (host: cmd: "  ${host}) echo ${lib.escapeShellArg cmd} ;;\n") claude
          )}
            *) echo claude ;;
          esac
        }
        start shell shell
        start claude claude local claude
        for host in $(mm hosts); do
          start "$host/shell" shell "$host"
          start "$host/claude" claude "$host" "$(claude_on "$host")"
        done
        if [ -t 1 ] && [ -z "''${MM_SESSION:-}" ]; then
          exec mm attach shell
        fi
      '';
    })
  ];
}
