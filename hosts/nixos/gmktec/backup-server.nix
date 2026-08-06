{ config, pkgs, ... }:

{
  # ── Backup target for trigkey ────────────────────────────────────────────────
  # gmktec holds the only off-machine copy of trigkey's data. restic pushes to
  # the REST server here; the repository lives on the Samsung T7 external SSD,
  # not on the internal NVMe, so a failure of either disk loses only one copy.
  #
  # The T7 previously held a stale Immich instance. Its upload set was verified
  # to be a strict subset of the live Immich on trigkey before it was wiped and
  # reformatted as ext4 on 2026-08-06.

  # ── T7 external SSD ──────────────────────────────────────────────────────────
  # nofail so the machine still boots if the drive is unplugged. The rest-server
  # unit below requires the mount, so a missing disk fails the service loudly
  # instead of silently filling the internal SSD.
  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/e1cf24a8-9f13-4925-89ec-ad97bbe5d61a";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=10"
    ];
  };

  # ── Credentials ──────────────────────────────────────────────────────────────
  # restic/htpasswd holds a single bcrypt line for the `trigkey` user, generated
  # with: htpasswd -nbB trigkey <password>
  # The matching password is embedded in trigkey's restic/repository URL.
  sops.secrets."restic/htpasswd" = {
    owner = "restic";
    mode = "0400";
  };

  # ── restic REST server ───────────────────────────────────────────────────────
  # appendOnly is intentionally OFF. trigkey runs `forget --prune` to apply the
  # retention policy, which append-only mode blocks. Turning it on would harden
  # the repo against a compromised trigkey, at the cost of unbounded growth and
  # manual pruning here.
  services.restic.server = {
    enable = true;
    listenAddress = "8000"; # socket-activated; port number only
    dataDir = "/mnt/backup/restic";
    htpasswd-file = config.sops.secrets."restic/htpasswd".path;
    appendOnly = false;
    prometheus = true; # /metrics, scraped via the node job's host
  };

  # Refuse to start unless the T7 is actually mounted, and create the repository
  # directory from inside the unit rather than via tmpfiles. systemd-tmpfiles
  # runs before the mount, so a tmpfiles rule would create the directory on the
  # internal disk and the mount would then hide it. Ordering it here also means
  # an unplugged T7 fails the service loudly instead of silently backing up to
  # the internal SSD.
  systemd.services.restic-rest-server = {
    unitConfig.RequiresMountsFor = "/mnt/backup";
    # "+" runs this outside the service sandbox, so it succeeds before the main
    # process sets up its mount namespace over the same path.
    serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/install -d -m 0700 -o restic -g restic /mnt/backup/restic";
  };

  # ── Storage tooling ──────────────────────────────────────────────────────────
  # This host now owns a disk. Keep the tools to inspect and repair it present
  # rather than reaching for `nix shell` during an incident.
  environment.systemPackages = with pkgs; [
    restic # restore from the repository locally if trigkey is gone
    e2fsprogs
    parted
    smartmontools
  ];

  # ── Firewall ─────────────────────────────────────────────────────────────────
  # Port 8000 is reachable from trigkey only. nftables is needed for
  # extraInputRules; trigkey gets it from incus.nix, this host has no Incus.
  networking.nftables.enable = true;
  networking.firewall.extraInputRules = ''
    ip saddr 192.168.0.202 tcp dport 8000 accept comment "restic REST from trigkey"
  '';
}
