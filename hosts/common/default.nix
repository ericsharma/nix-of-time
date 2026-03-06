{ config, lib, pkgs, ... }:

{
  imports = [
    ./sops.nix
    ./incus.nix
  ];

  # ── Nix ──────────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  # ── Timezone ─────────────────────────────────────────────────────────────────
  time.timeZone = "America/New_York";

  # ── nix-ld: lets unpatched ELF binaries run (native installers, etc.) ────────
  programs.nix-ld.enable = true;

  # ── User ─────────────────────────────────────────────────────────────────────
  users.users.eric = {
    isNormalUser = true;
    extraGroups  = [ "wheel" "incus-admin" ];
    # Password managed via sops-nix secrets
    hashedPasswordFile = config.sops.secrets."user-password/eric".path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQ4z1+PkPXFCY7Ts9XJbchYdT/oGKpifwdWK/axxf2H eric@ericsharma.xyz"
    ];
  };

  # Require password for sudo (password managed via sops-nix)
  security.sudo.wheelNeedsPassword = true;

  # ── SSH ──────────────────────────────────────────────────────────────────────
  services.openssh.enable                          = true;
  services.openssh.settings.PermitRootLogin        = "no";
  services.openssh.settings.PasswordAuthentication = false;

  # ── System packages ──────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    wget
    sops  # For editing encrypted secrets
  ];
}
