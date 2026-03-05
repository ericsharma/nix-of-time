{
  description = "Eric's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
  in {
    # System configuration — apply with:
    #   sudo nixos-rebuild switch --flake .#nixos
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ ./nixos/configuration.nix ];
    };

    # Dev shell for Claude Code and Node.js tooling
    # Enter with: nix develop
    devShells.${system}.default = pkgs.mkShell {
      name = "claude-dev";
      packages = with pkgs; [
        nodejs_22
        nodePackages.npm
      ];
      shellHook = ''
        echo "Claude Code dev shell — $(node --version)"
        echo "Install Claude Code:  npm install -g @anthropic-ai/claude-code"
        echo "Or use the native installer once nix-ld is active on the rebuilt system."
      '';
    };
  };
}
