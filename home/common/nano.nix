{ ... }:

{
  # Nano itself is configured at the NixOS level (hosts/common/default.nix);
  # this just pins EDITOR/VISUAL so sops, git, etc. reach for nano.
  home.sessionVariables = {
    EDITOR = "nano";
    VISUAL = "nano";
  };
}
