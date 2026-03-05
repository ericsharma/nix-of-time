{
  description = "Eric's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }: let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      # Apply with: sudo nixos-rebuild switch --flake .#trigkey
      trigkey = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/trigkey ];
      };

      # Future hosts:
      # laptop = nixpkgs.lib.nixosSystem { ... modules = [ ./hosts/laptop ]; };
    };

    # Dev shell — enter with: nix develop
    devShells.${system}.default = pkgs.mkShell {
      name = "claude-dev";
      packages = with pkgs; [
        nodejs_22
      ];
      shellHook = ''
        echo "Use the native Claude Code installer (recommended):"
        echo "  curl -fsSL https://claude.ai/install.sh | sh"
        echo "nix-ld is enabled system-wide so the installer works after a rebuild."
      '';
    };
  };
}
