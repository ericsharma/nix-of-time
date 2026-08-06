{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Unlike trigkey, this host does NOT glob all of ../optional. Those modules
  # carry no enable flags — each one turns its service on unconditionally, and
  # many are bound to trigkey's hardware (Immich mount, Garage, Newt tunnel,
  # the Incus LXC). List the wanted modules explicitly instead.
  imports = [
    ./hardware-configuration.nix
    ../common
    ../optional/monitoring/exporters.nix # node_exporter :9100, cAdvisor :9101
    ./backup-server.nix # restic REST server on the T7 external SSD
    ./meshllm.nix # local OpenAI-compatible inference API on :9337 (loopback)

    # Deliberately NOT imported:
    #   ../optional/tailscale.nix — the sops secret tailscale/authkey is a
    #     single-use key already consumed by trigkey. Mint a second key, store
    #     it under its own sops name, then import a host-local variant.
  ];

  # ── Boot ─────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ── Networking ───────────────────────────────────────────────────────────────
  networking.hostName = "gmktec";
  networking.useDHCP = false;
  networking.interfaces.enp1s0.useDHCP = true;

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];

  # llama-server, launched by hand for ad-hoc inference. Scoped to the LAN
  # subnet rather than added to allowedTCPPorts, which would also accept from
  # any other interface. The server has no authentication of any kind, so
  # whoever can reach the port can use the model and read every prompt — keep
  # this off the public path. Requires `--host 0.0.0.0` on llama-server; the
  # default 127.0.0.1 bind makes the rule inert.
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.0/24 tcp dport 8081 accept comment "llama-server from LAN"
  '';

  # ── Swap ─────────────────────────────────────────────────────────────────────
  # 32 GB of RAM and no swap partition on the 1 TB SSD. zram covers the rare
  # spike without a permanent on-disk partition.
  zramSwap.enable = true;

  # ── llama.cpp ────────────────────────────────────────────────────────────────
  # The CLI tools only — no `services.llama-cpp`. That module runs a second
  # llama-server, and MeshLLM (./meshllm.nix) already serves an OpenAI-compatible
  # API on :9337. Enable it here only if you want a dedicated second endpoint,
  # and give it a port other than 9337.
  #
  # From nixos-unstable, not 25.11. Stable ships build 6981, which predates the
  # `gemma4` architecture and fails to load those GGUFs with
  # "unknown model architecture: 'gemma4'". Unstable is on 9190 and supports it.
  # llama.cpp adds architectures constantly, so a stable channel is always some
  # months behind whatever model you just downloaded — this is exactly the
  # fast-moving-package case the unstable overlay in flake.nix exists for.
  #
  # CPU-only build. Same reasoning as MeshLLM: the 5825U's Vega iGPU shares DDR4
  # bandwidth with the CPU, so a Vulkan build rarely beats 8 threads here and
  # pulls in a mesa userspace.
  environment.systemPackages = [ pkgs.unstable.llama-cpp ];

  # Lets eric read MeshLLM's model cache, so llama.cpp can reuse the Qwen3-4B
  # GGUF already on disk instead of downloading a second 2.5 GB copy. The state
  # dir is 0750 mesh-llm:mesh-llm, so group membership is what grants this.
  # Nothing in there is sensitive — it is a re-derivable model and runtime cache —
  # and eric already has passwordless sudo, so this is no privilege increase.
  users.users.eric.extraGroups = [ "mesh-llm" ];

  # ── Sudo ─────────────────────────────────────────────────────────────────────
  # Same reasoning as trigkey: single-user homelab, SSH key-only, so passwordless
  # sudo for wheel keeps remote rebuilds non-interactive.
  security.sudo.wheelNeedsPassword = false;

  # ── SSH access from trigkey ──────────────────────────────────────────────────
  # ../common authorises only the eric@ericsharma.xyz workstation key. trigkey
  # holds a different key, so add it here (host-local, not in ../common) to let
  # trigkey drive remote rebuilds of this host.
  users.users.eric.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO5VwnSo02kL3IXOVayB8NGXykpqML1aysXuxX5iLhjS trigkey"
  ];

  # ── Remote deploys from trigkey ──────────────────────────────────────────────
  # `nixos-rebuild --target-host eric@gmktec` pushes an unsigned closure, which
  # the daemon refuses unless the SSH user is trusted. eric already has
  # passwordless sudo here, so this grants no new privilege.
  nix.settings.trusted-users = [
    "root"
    "eric"
  ];

  # ── State version — do not change after initial install ──────────────────────
  system.stateVersion = "25.11";
}
