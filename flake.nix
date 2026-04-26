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

    pirousync = {
      url   = "git+ssh://git@github.com/ericsharma/PiroueSync";
      flake = false;
    };

    belle-watson-studios = {
      url   = "git+ssh://git@github.com/baddiebelle/Belle-Watson-Studios";
      flake = false;
    };

    # jzstern's hardened YouTube PO token sidecar for Cobalt. We build only
    # services/yt-token/ via Dockerfile.yt-token (see hosts/docker-services/
    # services/cobalt.nix). Update with: nix flake update dub-rip
    dub-rip = {
      url   = "github:jzstern/dub-rip";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, sops-nix, home-manager, pirousync, belle-watson-studios, dub-rip }: let
    system = "x86_64-linux";
    pkgs   = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations = {
      # Apply with: sudo nixos-rebuild switch --flake .#trigkey
      trigkey = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit pirousync belle-watson-studios; };
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

      # docker-services Incus LXC container running on trigkey
      # Deploy: nixos-rebuild switch --flake .#docker-services --target-host root@10.0.100.10 --build-host localhost
      docker-services = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit dub-rip; };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/docker-services
        ];
      };

      # Future hosts:
      # laptop = nixpkgs.lib.nixosSystem { ... modules = [ ./hosts/laptop ]; };
    };

  };
}
