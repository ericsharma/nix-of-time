{
  description = "Eric's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, home-manager }: let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      # Apply with: sudo nixos-rebuild switch --flake .#trigkey
      trigkey = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.users.eric = import ./home/trigkey;
          }
          ./hosts/trigkey
        ];
      };

      # Future hosts:
      # laptop = nixpkgs.lib.nixosSystem { ... modules = [ ./hosts/laptop ]; };
    };

  };
}
