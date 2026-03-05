{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  # ── Nix ────────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── Boot ───────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Networking: DHCP Ethernet only, no Wi-Fi, no NetworkManager ────────────
  networking.hostName  = "nixos";
  networking.useDHCP   = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall.enable          = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # ── Timezone ───────────────────────────────────────────────────────────────
  # time.timeZone = "America/New_York";

  # ── nix-ld: lets unpatched ELF binaries run (native installers, npm CLIs) ──
  programs.nix-ld.enable = true;

  # ── SSH ────────────────────────────────────────────────────────────────────
  services.openssh.enable                            = true;
  services.openssh.settings.PermitRootLogin          = "prohibit-password";
  services.openssh.settings.PasswordAuthentication   = false;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFQ4z1+PkPXFCY7Ts9XJbchYdT/oGKpifwdWK/axxf2H eric@ericsharma.xyz"
  ];

  # ── System packages ────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    nodejs_22
  ];

  # ── State version — do not change after initial install ───────────────────
  system.stateVersion = "25.11";
}
