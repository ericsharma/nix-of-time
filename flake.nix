{
  description = "Eric's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix }: let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      # Apply with: sudo nixos-rebuild switch --flake .#trigkey
      trigkey = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/trigkey
        ];
      };

      # Future hosts:
      # laptop = nixpkgs.lib.nixosSystem { ... modules = [ ./hosts/laptop ]; };
    };

  };
}
