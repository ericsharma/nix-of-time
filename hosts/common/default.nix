{ config, lib, pkgs, ... }:

{
  imports = [
    ./sops.nix
  ];

  # ── Nix ──────────────────────────────────────────────────────────────────────
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── Generation management ─────────────────────────────────────────────────────
  # Limit boot entries to prevent bootloader failures from stale store paths.
  boot.loader.systemd-boot.configurationLimit = 10;

  # nh (Nix Helper): ergonomic wrapper around nixos-rebuild with nvd diffs
  # and a cleaner GC interface. Replaces nix.gc.automatic.
  programs.nh = {
    enable = true;
    flake  = "/home/eric/nixos-config";
    clean = {
      enable    = true;
      dates     = "weekly";
      extraArgs = "--keep 5 --keep-since 30d";
    };
  };

  # Deduplicate identical store files after each build.
  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  # ── Timezone ─────────────────────────────────────────────────────────────────
  time.timeZone = "America/New_York";

  # ── nix-ld: lets unpatched ELF binaries run (native installers, etc.) ────────
  programs.nix-ld.enable = true;

  # ── nano (system-wide config + syntax highlighting) ──────────────────────────
  programs.nano = {
    enable = true;
    syntaxHighlight = true;
    nanorc = ''
      set linenumbers
      set mouse
      set softwrap
      set atblanks
      set smarthome
      set tabsize 4
      set tabstospaces
      set autoindent
      set constantshow
      set indicator
      set zap
      set historylog
      set positionlog

      # Nord-aligned color theme (matches bat)
      set titlecolor       white,blue
      set statuscolor      white,blue
      set numbercolor      cyan
      set keycolor         cyan
      set functioncolor    blue
      set selectedcolor    white,magenta
      set stripecolor      ,magenta
      set scrollercolor    cyan
      set errorcolor       white,red
    '';
  };

  # ── User ─────────────────────────────────────────────────────────────────────
  users.users.eric = {
    isNormalUser = true;
    linger       = true;
    extraGroups  = [ "wheel" ];
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
