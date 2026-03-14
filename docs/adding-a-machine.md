# Adding a new machine

1. Create the host directory:
   ```
   hosts/<name>/
   ├── default.nix
   └── hardware-configuration.nix
   ```

2. In `default.nix`, import the shared config:
   ```nix
   { config, lib, pkgs, ... }:

   {
     imports = [
       ./hardware-configuration.nix
       ../common
       # Add optional modules as needed:
       # ../optional/monitoring.nix
       # ../optional/syncthing.nix
     ];

     networking.hostName = "<name>";

     system.stateVersion = "25.11";  # Set to your NixOS version at install time
   }
   ```

3. Generate `hardware-configuration.nix` on the target machine:
   ```bash
   nixos-generate-config --show-hardware-config > hardware-configuration.nix
   ```

4. Add the host to `flake.nix` as a new `nixosConfigurations` entry.

5. If the host needs to decrypt secrets, add it as a sops recipient — see [secrets.md](secrets.md#adding-a-new-sops-recipient).

6. Optionally create a home-manager config at `home/<name>/default.nix`.
