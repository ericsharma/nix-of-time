{ modulesPath, lib, pkgs, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/lxc-container.nix")
    ./sops.nix

    ./services/koito.nix
    ./services/karakeep.nix
    ./services/dawarich.nix
    ./services/periphery.nix
    ./services/cadvisor.nix
    ./services/city-gifs.nix
    ./services/keeper.nix
    ./services/rybbit.nix
    ./services/cobalt.nix
  ];

  # ── LXC container ────────────────────────────────────────────────────────
  boot.isContainer = true;
  networking.hostName = "docker-services";
  networking.useDHCP  = true;

  # Guard: abort activation if this config is applied to the wrong host.
  # Prevents accidentally writing a docker-services generation to the trigkey
  # system profile (which corrupts the bootloader's boot entry list).
  system.activationScripts.check-hostname = ''
    actual=$(cat /proc/sys/kernel/hostname)
    expected="docker-services"
    if [ "$actual" != "$expected" ]; then
      echo "ERROR: This config is for $expected but activating on $actual." >&2
      echo "Use --target-host root@10.0.100.10 to deploy to the LXC container." >&2
      exit 1
    fi
  '';

  # ── Docker (multi-container DNS works out of the box) ────────────────────
  virtualisation.docker.enable = true;
  virtualisation.oci-containers.backend = "docker";

  # ── SSH (for nixos-rebuild --target-host from trigkey) ───────────────────
  services.openssh.enable                          = true;
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.PermitRootLogin        = "prohibit-password";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQ4z1+PkPXFCY7Ts9XJbchYdT/oGKpifwdWK/axxf2H eric@ericsharma.xyz"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5VwnSo02kL3IXOVayB8NGXykpqML1aysXuxX5iLhjS trigkey"
  ];

  # ── System packages ───────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = [ pkgs.vim pkgs.docker ];

  system.stateVersion = "25.11";
}
