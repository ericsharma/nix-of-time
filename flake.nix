{
  description = "Eric's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Escape hatch for individual fast-moving packages (Immich, Karakeep,
    # Dawarich, etc.). Reference as `pkgs.unstable.<name>`.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pirousync = {
      url = "git+ssh://git@github.com/ericsharma/PiroueSync";
      flake = false;
    };

    p2poker = {
      url = "git+ssh://git@github.com/ericsharma/p2poker";
      flake = false;
    };

    belle-watson-studios = {
      url = "git+ssh://git@github.com/ericsharma/Belle-Watson-Studios";
      flake = false;
    };

    options-ledger = {
      url = "git+ssh://git@github.com/ericsharma/options-ledger";
      flake = false;
    };

    # EternaTV (LoC video stream orchestrator + HLS player). Real flake — the
    # NixOS module in hosts/nixos/optional/radio-video.nix consumes
    # `eternatv.packages.<system>.{eternatv,eternatv-player}` and writes a JSON
    # config that the orchestrator reads at startup.
    eternatv = {
      url = "git+ssh://git@github.com/ericsharma/eternatv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # jzstern's hardened YouTube PO token sidecar for Cobalt. We build only
    # services/yt-token/ via Dockerfile.yt-token (see hosts/docker-services/
    # services/cobalt.nix). Update with: nix flake update dub-rip
    dub-rip = {
      url = "github:jzstern/dub-rip";
      flake = false;
    };

    # Nous Research's Hermes Agent. Exposes nixosModules.default which the
    # trigkey config consumes via hosts/nixos/optional/hermes-agent.nix.
    # We intentionally do NOT set inputs.nixpkgs.follows: hermes-agent is
    # built with uv2nix against nixos-unstable and pinning it to 25.11 has
    # historically broken the Python venv build. Pay the extra nixpkgs in
    # the closure rather than risk eval breakage on every flake update.
    hermes-agent.url = "github:NousResearch/hermes-agent";

  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      sops-nix,
      home-manager,
      pirousync,
      p2poker,
      belle-watson-studios,
      options-ledger,
      dub-rip,
      eternatv,
      hermes-agent,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Inject `pkgs.unstable.*` into every module's pkgs argument so any
      # service can reach into nixos-unstable for a single package without
      # bumping the whole channel.
      unstableOverlay = final: _prev: {
        unstable = import nixpkgs-unstable {
          inherit system;
          config = final.config;
        };
      };

      localPackagesOverlay = final: _prev: {
        grok-build = final.callPackage ./pkgs/grok-build.nix { };
        pai-sho = final.callPackage ./pkgs/pai-sho.nix { };
        media-to-ascii = final.callPackage ./pkgs/media-to-ascii.nix { };
      };

      commonModules = [
        sops-nix.nixosModules.sops
        {
          nixpkgs.overlays = [
            unstableOverlay
            localPackagesOverlay
          ];
        }
      ];

      inventory = import ./inventory.nix;
    in
    {
      nixosConfigurations = {
        # Apply with: sudo nixos-rebuild switch --flake .#trigkey
        trigkey = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              pirousync
              p2poker
              belle-watson-studios
              options-ledger
              eternatv
              hermes-agent
              inventory
              ;
          };
          modules = commonModules ++ [
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = { };
              home-manager.users.eric = import ./home/trigkey;
            }
            ./hosts/nixos/trigkey
          ];
        };

        # docker-services Incus LXC container running on trigkey
        # Deploy: nixos-rebuild switch --flake .#docker-services --target-host root@10.0.100.10 --build-host localhost
        docker-services = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit dub-rip inventory; };
          modules = commonModules ++ [
            ./hosts/nixos/docker-services
          ];
        };

        # Future hosts:
        # laptop = nixpkgs.lib.nixosSystem { ... modules = [ ./hosts/laptop ]; };
      };

      # `nix run .#pai-sho -- daemon -a <ticket>` connects from a Linux laptop.
      # macOS: use `brew install cablehead/tap/pai-sho` instead.
      packages.${system}.pai-sho = pkgs.callPackage ./pkgs/pai-sho.nix { };

      # `nix fmt` formats every .nix file in the repo.
      formatter.${system} = pkgs.nixfmt-rfc-style;

      # `nix develop` drops you into a shell with the tools needed to operate
      # the repo: edit secrets, derive age keys, format Nix.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          sops
          age
          ssh-to-age
          nixfmt-rfc-style
          nh
        ];
      };

      # `nix flake check` evaluates each host's toplevel — catches eval errors
      # in any module before you `rebuild` against the live system.
      checks.${system} = {
        trigkey = self.nixosConfigurations.trigkey.config.system.build.toplevel;
        docker-services = self.nixosConfigurations.docker-services.config.system.build.toplevel;
      };
    };
}
